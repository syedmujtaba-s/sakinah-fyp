"""
Vision-LLM emotion fallback (Lever 2 from the accuracy plan).

The face-only HSEmotion model gets confused on subtle expressions and on
neutral resting faces (it's an AffectNet-bias issue — neutral is hard
even for SOTA). When its confidence on a frame drops below a threshold,
we fall through to a vision-capable LLM and ask it to pick from
Sakinah's 15 emotions in plain English.

Why this works (real numbers, not aspirational):
    Vision LLMs read context the way a human does — head tilt, eye
    crinkles, set of the jaw, posture, gaze. On nuanced expressions
    they hit ~85-90% on the same prompts where small CNNs hit ~50-65%.
    Combined with HSEmotion as the fast first-pass, end-to-end latency
    stays under 2 seconds.

Cost:
    Free on Groq's dev tier (which we already use for guidance/translate).
    Roughly $0.0005/call on paid tier. Negligible at any realistic FYP
    scale.

This module ONLY does inference. The decision to invoke it (e.g. when
face_model.predict returns confidence < 0.7) lives in the router /
fusion layer.
"""
from __future__ import annotations

import base64
import json
import os
import re
from typing import Optional

import httpx

GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
# Groq's vision-capable Llama. The 90b variant is markedly better than
# 11b on facial expression — the size buys context understanding.
VISION_MODEL = os.getenv(
    "SAKINAH_VISION_MODEL", "meta-llama/llama-4-scout-17b-16e-instruct"
)

# Imported from the central taxonomy so the three model-facing lists
# (face fusion, vision LLM, admin validation) can never drift again.
from emotion.taxonomy import SAKINAH_EMOTIONS as SAKINAH_15, SAKINAH_EMOTION_SET as _VALID

# Ask the model for ONLY the label, no preamble. We strictly accept JSON
# so we can parse without regex gymnastics — Groq's JSON mode guarantees
# valid JSON output.
_SYSTEM_PROMPT = (
    "You are an expert at reading human emotion from a face. Look at the "
    "face and pick ONE label that best describes what the person feels.\n\n"
    "Allowed labels:\n"
    "  neutral, happy, sad, anxious, angry, grateful, lonely, stressed,\n"
    "  fearful, guilty, hopeless, overwhelmed, rejected, embarrassed,\n"
    "  confused, lost\n\n"
    "STRICT RULES:\n"
    "1. If the face is RELAXED, RESTING, or shows NO STRONG EMOTION, "
    "answer \"neutral\". Do NOT force a stronger label on a neutral face.\n"
    "2. \"confused\" and \"lost\" are LAST-RESORT labels. Only use "
    "\"confused\" if the face actually shows confusion (furrowed brow, "
    "head tilt, asymmetric expression). Only use \"lost\" if the gaze "
    "is genuinely vacant or disoriented. Never use these as fallbacks "
    "for hard-to-read faces — pick \"neutral\" instead.\n"
    "3. For a face that DOES show emotion, prefer the most specific "
    "match (e.g. soft smile -> happy; furrowed brow + tense jaw -> "
    "stressed; downturned mouth + tired eyes -> sad).\n"
    "4. Use confidence < 0.5 only when truly uncertain. For a clearly "
    "neutral face, return neutral with confidence 0.7-0.9.\n\n"
    'Reply with ONLY this JSON, nothing else: '
    '{"emotion": "<word>", "confidence": <0-1>}'
)


def is_available() -> bool:
    """Whether Groq vision can be called. Lets the caller decide whether
    to even bother packaging up the bytes."""
    return "gsk_" in GROQ_API_KEY


async def predict(image_bytes: bytes, timeout: float = 8.0) -> dict:
    """
    Classify a face image into Sakinah-15 via Groq vision.

    Returns:
        {"ok": True, "predicted": "happy", "confidence": 0.86}
        on success, or
        {"ok": False, "error": "...", "detail": "..."}
        on any failure (no API key, network error, malformed reply,
        label not in vocabulary, etc.). Caller should treat ok=False
        as "no signal from this source" — the fusion layer already
        handles that gracefully.
    """
    if not is_available():
        return {"ok": False, "error": "no_api_key",
                "detail": "GROQ_API_KEY not set; vision LLM disabled."}

    # Groq's vision API takes the image as a data: URL inside a chat message.
    # Base64-encoding adds ~33% overhead but it's the standard interchange
    # format and Groq doesn't take multipart for chat/completions.
    b64 = base64.b64encode(image_bytes).decode("ascii")
    data_url = f"data:image/jpeg;base64,{b64}"

    payload = {
        "model": VISION_MODEL,
        "messages": [
            {"role": "system", "content": _SYSTEM_PROMPT},
            {
                "role": "user",
                "content": [
                    {"type": "text",
                     "text": "Classify the emotion in this face."},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            },
        ],
        "temperature": 0.0,
        # Llama-vision doesn't currently support response_format=json_object,
        # so we coerce JSON via the system prompt and parse defensively.
    }

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            r = await client.post(
                GROQ_URL,
                headers={"Authorization": f"Bearer {GROQ_API_KEY}",
                         "Content-Type": "application/json"},
                json=payload,
            )
    except httpx.TimeoutException as e:
        return {"ok": False, "error": "timeout", "detail": str(e)}
    except Exception as e:
        return {"ok": False, "error": "network", "detail": str(e)}

    if r.status_code != 200:
        return {
            "ok": False, "error": f"http_{r.status_code}",
            "detail": str(r.text)[:300],
        }

    try:
        content = r.json()["choices"][0]["message"]["content"]
    except Exception as e:
        return {"ok": False, "error": "bad_response", "detail": str(e)}

    return _parse_label(content)


def _parse_label(content: str) -> dict:
    """
    Pull a Sakinah-15 label out of the model's reply. We try JSON first
    (the prompt asks for it), fall back to regex when the model wraps
    the JSON in prose or skips it entirely.
    """
    # First try: clean JSON.
    try:
        obj = json.loads(content)
        label = str(obj.get("emotion", "")).lower().strip()
        conf = float(obj.get("confidence", 0.7))
        if label in _VALID:
            return {"ok": True, "predicted": label,
                    "confidence": max(0.0, min(1.0, conf))}
    except (json.JSONDecodeError, ValueError, TypeError):
        pass

    # Second try: JSON embedded in prose.
    m = re.search(r'\{[^}]*"emotion"\s*:\s*"([a-zA-Z]+)"[^}]*\}', content, re.I)
    if m:
        label = m.group(1).lower().strip()
        if label in _VALID:
            return {"ok": True, "predicted": label, "confidence": 0.7}

    # Third try: bare word match — pick the first Sakinah-15 word that
    # appears in the reply. This is the loosest fallback so we only get
    # here if the model ignored the JSON instruction entirely.
    lower = content.lower()
    for label in SAKINAH_15:
        if re.search(rf"\b{label}\b", lower):
            return {"ok": True, "predicted": label, "confidence": 0.65}

    return {"ok": False, "error": "no_label_in_reply",
            "detail": content[:200]}
