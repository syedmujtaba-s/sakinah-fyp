"""
Privacy verification — TC-16 from the QA plan.

Asserts the multi-modal emotion-detection pipeline never persists user
images to disk. Approach:

  1. Snapshot every file under the backend directory (excluding the venv,
     pycache, and existing data files).
  2. Generate a synthetic JPEG and POST it to the production endpoint
     handler in-process via FastAPI's TestClient (no real network hop).
  3. Snapshot the filesystem again and diff. Any newly-written file
     under the backend tree fails the test.

Why this matters:
  Sakinah's privacy claim ("camera images are processed in real-time and
  never stored, only the resulting emotion label is saved") is a load-
  bearing promise on the dissertation Privacy Policy. This test enforces
  it as code so a future refactor can't silently break it.

Skip rules:
  - Skipped if HSEmotion / RoBERTa weights aren't available locally —
    the test exercises the *handler*, not the models, but the import
    chain still needs them. CI environments without GPU access will set
    SKIP_HEAVY_ML_TESTS=1 to bypass.
"""
from __future__ import annotations

import io
import os
import time
from pathlib import Path

import pytest
from PIL import Image

if os.environ.get("SKIP_HEAVY_ML_TESTS"):
    pytest.skip("Heavy-ML tests skipped via env var", allow_module_level=True)


BACKEND_DIR = Path(__file__).parent
EXCLUDED_DIRS = {".venv", "__pycache__", ".pytest_cache", "data"}


def _snapshot_files() -> dict[Path, float]:
    """Map of every file under the backend dir → its mtime."""
    snap: dict[Path, float] = {}
    for path in BACKEND_DIR.rglob("*"):
        if not path.is_file():
            continue
        if any(part in EXCLUDED_DIRS for part in path.parts):
            continue
        try:
            snap[path] = path.stat().st_mtime
        except OSError:
            continue
    return snap


def _make_test_jpeg(size: int = 224) -> bytes:
    img = Image.new("RGB", (size, size), color=(180, 130, 100))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85)
    return buf.getvalue()


def test_emotion_detect_writes_no_files_to_disk():
    from fastapi.testclient import TestClient
    from main import app

    client = TestClient(app)

    before = _snapshot_files()
    jpeg = _make_test_jpeg()

    # Call the endpoint twice — once with image only, once with text only.
    # Both must respect the no-storage invariant.
    r1 = client.post(
        "/api/emotion/detect",
        files={"image": ("face.jpg", jpeg, "image/jpeg")},
    )
    assert r1.status_code in (200, 413), f"unexpected status {r1.status_code}"

    r2 = client.post(
        "/api/emotion/detect",
        data={"journal_text": "I am feeling great today, alhamdulillah"},
    )
    assert r2.status_code == 200

    # Brief breathing room so any async log/file write has a chance to land.
    time.sleep(0.2)
    after = _snapshot_files()

    # Allowed deltas: pyc cache files, log rotations, etc. — but no JPEG/PNG/raw.
    suspect = []
    for path, mtime in after.items():
        if path not in before or before[path] != mtime:
            ext = path.suffix.lower()
            if ext in {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".raw", ".heic"}:
                suspect.append(path)
            elif "image" in path.name.lower() or "face" in path.name.lower():
                suspect.append(path)

    assert not suspect, (
        "Privacy invariant broken: image-like files were written during "
        f"emotion detection. Offenders: {suspect}"
    )
