"""
Single source of truth for the Sakinah emotion taxonomy.

Was previously duplicated across:
    backend/emotion/fusion.py        (SAKINAH_15)
    backend/emotion/vision_llm.py    (SAKINAH_15)
    backend/guidance_router.py       (SUPPORTED_EMOTIONS)
    backend/admin_router.py          (SUPPORTED_EMOTIONS)
    backend/test_api.py              (assertion against count == 15)
    backend/validate_jsonl.py        (separate copy)
    sakinah-admin/lib/services/*.dart (Dart copy)
    app/lib/screens/emotion_checkin_screen.dart (manual chip grid)

Codex review on 2026-05-02 caught that adding "neutral" updated some of
those copies but missed others — admin upload would reject neutral, the
Flutter chip grid had it, and the JS validation was inconsistent. This
file replaces the backend duplicates so any future addition (or removal)
to the taxonomy lives in exactly one place.

The Flutter app has its own mirror at app/lib/config/emotion_taxonomy.dart
which must be kept in sync.
"""
from __future__ import annotations

# Canonical Sakinah emotion list. Order matters for any UI that iterates
# this directly (manual chip grid, admin dropdowns) — "neutral" first
# because that's the default for a calm/resting state.
SAKINAH_EMOTIONS: list[str] = [
    "neutral",
    "happy",
    "sad",
    "anxious",
    "angry",
    "confused",
    "grateful",
    "lonely",
    "stressed",
    "fearful",
    "guilty",
    "hopeless",
    "overwhelmed",
    "rejected",
    "embarrassed",
    "lost",
]

# Set lookup is faster + clearer for "is this emotion supported" checks.
SAKINAH_EMOTION_SET: frozenset[str] = frozenset(SAKINAH_EMOTIONS)


def is_supported(emotion: str) -> bool:
    """Case-insensitive emotion validation."""
    return emotion.lower().strip() in SAKINAH_EMOTION_SET
