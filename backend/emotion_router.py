"""
Multi-modal emotion detection endpoint.

POST /api/emotion/detect
    Multipart form:
        image:        optional UploadFile (JPEG/PNG, <=2MB after client-side compression)
        journal_text: optional str
    At least ONE of (image, journal_text) must be provided.

GET /api/emotion/health
    Lightweight ping. Returns model-load status without forcing a load.

Privacy:
    Image bytes are read into memory, processed, and discarded. They are
    never written to disk and never persisted. Only the predicted emotion
    label + confidence is returned to the client (and ultimately stored in
    the user's journal entry alongside their text).

Rate limiting:
    Tiny in-memory limiter — 30 requests / 60s per (Authorization header or
    client IP). Good enough for an FYP / early production; swap for Redis
    when traffic grows.
"""
from __future__ import annotations

import asyncio
import time
from collections import defaultdict, deque
from typing import Optional

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import JSONResponse

from emotion import face_model, text_model, fusion
from models import EmotionDetectionResponse

router = APIRouter(prefix="/api/emotion", tags=["emotion"])

# --- Config ---
MAX_IMAGE_BYTES = 2 * 1024 * 1024     # 2 MB hard cap (client compresses to ~30KB)
RATE_LIMIT_WINDOW = 60                # seconds
RATE_LIMIT_MAX = 30                   # requests per window per client

_rate_buckets: dict[str, deque[float]] = defaultdict(deque)


def _client_key(request: Request) -> str:
    """Use Authorization header if present (Firebase ID token), else IP."""
    auth = request.headers.get("Authorization", "")
    if auth:
        # Use a hash-friendly suffix so tokens aren't logged verbatim.
        return f"auth:{hash(auth) & 0xFFFFFFFF:x}"
    if request.client:
        return f"ip:{request.client.host}"
    return "anon"


def _check_rate_limit(key: str) -> bool:
    """Return True if within limit, False if exceeded."""
    now = time.time()
    bucket = _rate_buckets[key]
    while bucket and now - bucket[0] > RATE_LIMIT_WINDOW:
        bucket.popleft()
    if len(bucket) >= RATE_LIMIT_MAX:
        return False
    bucket.append(now)
    return True


@router.post("/detect", response_model=EmotionDetectionResponse)
async def detect_emotion(
    request: Request,
    image: Optional[UploadFile] = File(None),
    journal_text: Optional[str] = Form(None),
):
    # ---- Rate limit ----
    if not _check_rate_limit(_client_key(request)):
        raise HTTPException(
            status_code=429,
            detail=f"Rate limit exceeded. Max {RATE_LIMIT_MAX} requests per {RATE_LIMIT_WINDOW}s."
        )

    # ---- Input validation ----
    has_image = image is not None and image.filename
    has_text = journal_text is not None and journal_text.strip()
    if not has_image and not has_text:
        raise HTTPException(
            status_code=400,
            detail="Provide at least one of 'image' or 'journal_text'.",
        )

    # ---- Run face + text in parallel where possible ----
    face_task = None
    text_task = None

    if has_image:
        image_bytes = await image.read()
        if len(image_bytes) > MAX_IMAGE_BYTES:
            raise HTTPException(
                status_code=413,
                detail=f"Image too large ({len(image_bytes)} bytes, max {MAX_IMAGE_BYTES}).",
            )
        # face_model.predict is sync (CPU-bound) — run in a thread to avoid
        # blocking the event loop.
        face_task = asyncio.to_thread(face_model.predict, image_bytes)

    if has_text:
        # text_model.predict is async (it may call Groq for translation).
        text_task = text_model.predict(journal_text)

    face_result: Optional[dict] = None
    text_result: Optional[dict] = None

    if face_task and text_task:
        face_result, text_result = await asyncio.gather(face_task, text_task)
    elif face_task:
        face_result = await face_task
    elif text_task:
        text_result = await text_task

    # ---- Fuse ----
    fused = fusion.fuse(face=face_result, text=text_result)

    # ---- Build response ----
    response = EmotionDetectionResponse(
        predicted_emotion=fused["predicted"],
        confidence=round(fused["confidence"], 4),
        scores={k: round(v, 4) for k, v in fused["scores"].items()},
        sources_used=fused["sources_used"],
        fusion_strategy=fused["fusion_strategy"],
        low_confidence=fused["low_confidence"],
        face_predicted=fused.get("face_predicted"),
        face_confidence=round(fused.get("face_confidence", 0.0), 4),
        valence=face_result.get("valence") if face_result else None,
        arousal=face_result.get("arousal") if face_result else None,
        text_predicted=fused.get("text_predicted"),
        text_confidence=round(fused.get("text_confidence", 0.0), 4),
        text_translated=bool(text_result and text_result.get("translated")),
    )

    # When face was attempted but no face was detected, surface a helpful hint
    # in the HTTP response — the UI shows "Couldn't read your face — try again
    # or pick manually" rather than failing silently.
    if has_image and face_result and not face_result.get("ok"):
        return JSONResponse(
            status_code=200,
            content={
                **response.model_dump(),
                "face_error": face_result.get("error"),
                "face_error_detail": face_result.get("detail"),
            },
        )

    return response


@router.get("/health")
def health():
    """Lightweight ping. Does not trigger model loads."""
    from emotion.face_model import _recognizer as _fer
    from emotion.text_model import _pipeline as _txt
    return {
        "status": "ok",
        "service": "sakinah-emotion-api",
        "face_model_loaded": _fer is not None,
        "text_model_loaded": _txt is not None,
    }
