"""
Text emotion classification with multilingual support via Groq translation.

Pipeline:
  1. Detect whether the text is English or non-English (heuristic).
  2. If non-English (e.g. Roman Urdu) -> ask Groq to translate to English.
     This reuses the same Groq credentials/model already configured for
     guidance generation (see guidance_router.py).
  3. Run DistilRoBERTa-emotion on the English text and return 7-class probs.

Labels (j-hartmann/emotion-english-distilroberta-base):
    anger, disgust, fear, joy, neutral, sadness, surprise.
"""
from __future__ import annotations

import os
import re
from typing import Optional

import httpx

# Lazy singletons.
_pipeline = None
_torch = None

GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL = "llama-3.3-70b-versatile"

ROBERTA_LABELS = ["anger", "disgust", "fear", "joy", "neutral", "sadness", "surprise"]


def _get_pipeline():
    """Lazy-load DistilRoBERTa-emotion. ~270MB on disk, downloads on first run."""
    global _pipeline, _torch
    if _pipeline is None:
        import torch
        from transformers import AutoModelForSequenceClassification, AutoTokenizer

        _torch = torch
        print("[text_model] Loading j-hartmann/emotion-english-distilroberta-base...")
        model_name = "j-hartmann/emotion-english-distilroberta-base"
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model = AutoModelForSequenceClassification.from_pretrained(model_name)
        model.eval()
        _pipeline = (tokenizer, model)
        print("[text_model] Text emotion model ready.")
    return _pipeline


def warmup() -> None:
    """Pre-load the text classifier. Called from main.py startup."""
    _get_pipeline()


# --------------------------------------------------------------------------
# Language detection — cheap heuristic, no extra dependency.
# --------------------------------------------------------------------------
# Common Roman Urdu words/markers and Hindi-ish particles. Hit-rate is high
# on the kind of code-mixed Urdu Pakistani users actually write.
_ROMAN_URDU_MARKERS = {
    "hai", "hain", "ho", "hoon", "hun", "the", "thi", "tha",
    "nahi", "nai", "nahin", "ne", "ko", "ka", "ki", "ke",
    "mujhe", "mujhko", "mera", "meri", "mere", "tum", "tumhe",
    "kaam", "yar", "yaar", "bhai", "behen",
    "khtm", "khatam", "raha", "rha", "rahi", "rhi", "rahe", "rhe",
    "dimaag", "dil", "zindagi", "khushi",
    "kyon", "kyun", "kyu", "matlab", "agar", "warna",
    "achha", "acha", "buri", "bura", "behtar",
    "thakaa", "thak", "udaas", "pareshan", "ghussa",
}


def _looks_non_english(text: str) -> bool:
    """
    Return True if the text appears to be Roman Urdu / non-English.

    Strategy: tokenize on whitespace, count how many tokens are common English
    *vs.* Roman Urdu markers. If >= 2 markers OR markers > english words, treat
    as non-English. This is intentionally lenient — false positives just mean
    we run a translation that costs ~300ms.
    """
    if not text or not text.strip():
        return False

    # Strip non-letters, lowercase.
    tokens = re.findall(r"[a-zA-Z']+", text.lower())
    if not tokens:
        return False

    marker_hits = sum(1 for t in tokens if t in _ROMAN_URDU_MARKERS)
    if marker_hits >= 2:
        return True
    # If half the tokens or more are markers, treat as non-English.
    if marker_hits >= max(1, len(tokens) // 4):
        return True
    return False


# --------------------------------------------------------------------------
# Groq translation (only when needed).
# --------------------------------------------------------------------------
async def _translate_to_english(text: str) -> Optional[str]:
    """Ask Groq to translate Roman Urdu / Urdu / Hindi -> English. Returns
    None on failure so the caller can fall back to the original text."""
    if "gsk_" not in GROQ_API_KEY:
        return None

    sys_prompt = (
        "You are a precise translator. Translate the user's input to natural, "
        "modern English. The input may be Roman Urdu, Urdu, Hindi, or "
        "code-mixed English. Preserve the emotional tone exactly. Reply with "
        "ONLY the English translation — no quotes, no explanation, no notes."
    )
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            r = await client.post(
                GROQ_URL,
                headers={"Authorization": f"Bearer {GROQ_API_KEY}",
                         "Content-Type": "application/json"},
                json={
                    "model": GROQ_MODEL,
                    "messages": [
                        {"role": "system", "content": sys_prompt},
                        {"role": "user", "content": text},
                    ],
                    "temperature": 0.0,
                },
            )
        if r.status_code != 200:
            print(f"[text_model] Groq translate failed {r.status_code}: {r.text[:200]}")
            return None
        return r.json()["choices"][0]["message"]["content"].strip()
    except Exception as e:
        print(f"[text_model] Groq translate exception: {e}")
        return None


# --------------------------------------------------------------------------
# Main inference entry point.
# --------------------------------------------------------------------------
async def predict(text: str) -> dict:
    """
    Predict emotion probabilities from a journal text.

    Returns:
        {
            "ok": True,
            "predicted": "joy",
            "confidence": 0.83,
            "scores": {"anger": ..., "disgust": ..., ...},
            "translated": True | False,
            "english_text": "...",   # the text actually fed to the model
        }

    Empty/blank text returns ok=False so the fusion layer can skip the text signal.
    """
    if not text or len(text.strip()) < 3:
        return {"ok": False, "error": "text_too_short"}

    english_text = text
    translated = False

    if _looks_non_english(text):
        translated_text = await _translate_to_english(text)
        if translated_text:
            english_text = translated_text
            translated = True
        # else: fall back to the original text — DistilRoBERTa still picks up
        # English keywords sloppily mixed in.

    tokenizer, model = _get_pipeline()
    inputs = tokenizer(
        english_text,
        return_tensors="pt",
        truncation=True,
        max_length=512,
    )
    with _torch.no_grad():
        logits = model(**inputs).logits[0]
    probs = _torch.softmax(logits, dim=-1).tolist()

    scores = {ROBERTA_LABELS[i]: float(probs[i])
              for i in range(min(len(ROBERTA_LABELS), len(probs)))}
    predicted = max(scores, key=scores.get)
    confidence = float(scores[predicted])

    return {
        "ok": True,
        "predicted": predicted,
        "confidence": confidence,
        "scores": scores,
        "translated": translated,
        "english_text": english_text,
    }
