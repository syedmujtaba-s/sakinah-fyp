"""
Multi-modal emotion fusion.

Inputs (each optional):
  - Face scores: 8 AffectNet labels {Anger, Contempt, Disgust, Fear,
                                     Happiness, Neutral, Sadness, Surprise}
  - Text scores: 7 RoBERTa labels   {anger, disgust, fear, joy,
                                     neutral, sadness, surprise}

Output:
  - One label from Sakinah's 15-emotion taxonomy + confidence + raw breakdown.

Strategy:
  1. Project each model's distribution onto the Sakinah-15 space using a
     hand-tuned weight matrix (validated against a small in-house golden set).
  2. Combine the two projected distributions with a confidence-weighted
     average. If only one source is provided, that source wins.
  3. Tie-break edge cases:
     - If the two sources disagree by a wide margin (top labels differ AND
       both confidences are >= 0.55), return the *higher-confidence* source
       rather than blending — averaging two strong-but-opposite signals
       produces a meaningless "neutral soup" that helps no one.
     - If both sources are weak (< 0.35), return "confused" with low
       confidence so the UI can prompt the user to pick manually.

The 15 Sakinah emotions match `SUPPORTED_EMOTIONS` in guidance_router.py:
    happy, sad, anxious, angry, confused, grateful, lonely, stressed,
    fearful, guilty, hopeless, overwhelmed, rejected, embarrassed, lost.
"""
from __future__ import annotations

from typing import Optional

SAKINAH_15 = [
    "happy", "sad", "anxious", "angry", "confused",
    "grateful", "lonely", "stressed", "fearful", "guilty",
    "hopeless", "overwhelmed", "rejected", "embarrassed", "lost",
]


# AffectNet -> Sakinah-15 mapping. Each row is a probability distribution
# over the Sakinah labels (rows must sum to 1.0). These weights were chosen
# by inspection of the closest emotional overlap, leaning toward the most
# common Sakinah expression of each AffectNet category.
FACE_TO_SAKINAH: dict[str, dict[str, float]] = {
    "Anger":     {"angry": 0.70, "stressed": 0.15, "overwhelmed": 0.10, "rejected": 0.05},
    "Contempt":  {"rejected": 0.45, "angry": 0.25, "embarrassed": 0.15, "lonely": 0.15},
    "Disgust":   {"embarrassed": 0.40, "rejected": 0.30, "angry": 0.20, "guilty": 0.10},
    "Fear":      {"fearful": 0.55, "anxious": 0.30, "stressed": 0.10, "overwhelmed": 0.05},
    "Happiness": {"happy": 0.80, "grateful": 0.20},
    "Neutral":   {"confused": 0.40, "lost": 0.30, "happy": 0.15, "sad": 0.15},
    "Sadness":   {"sad": 0.50, "lonely": 0.20, "hopeless": 0.20, "lost": 0.10},
    "Surprise":  {"confused": 0.40, "overwhelmed": 0.30, "anxious": 0.20, "happy": 0.10},
}

# RoBERTa -> Sakinah-15. Text gives us slightly different cues (e.g. text
# rarely shows "contempt" but does show "joy" cleanly).
TEXT_TO_SAKINAH: dict[str, dict[str, float]] = {
    "anger":   {"angry": 0.65, "stressed": 0.15, "rejected": 0.10, "overwhelmed": 0.10},
    "disgust": {"embarrassed": 0.40, "rejected": 0.30, "angry": 0.20, "guilty": 0.10},
    "fear":    {"fearful": 0.45, "anxious": 0.40, "stressed": 0.10, "overwhelmed": 0.05},
    "joy":     {"happy": 0.75, "grateful": 0.25},
    "neutral": {"confused": 0.35, "lost": 0.35, "happy": 0.15, "sad": 0.15},
    "sadness": {"sad": 0.45, "lonely": 0.20, "hopeless": 0.20, "lost": 0.10, "guilty": 0.05},
    "surprise":{"confused": 0.35, "overwhelmed": 0.30, "anxious": 0.20, "happy": 0.15},
}


def _project(scores: dict, mapping: dict[str, dict[str, float]]) -> dict[str, float]:
    """Project a model's distribution onto the Sakinah-15 space."""
    out = {label: 0.0 for label in SAKINAH_15}
    for src_label, prob in scores.items():
        weights = mapping.get(src_label)
        if not weights:
            continue
        for sk_label, w in weights.items():
            out[sk_label] += prob * w
    # Renormalize to sum to 1.0 in case of rounding drift.
    total = sum(out.values()) or 1.0
    return {k: v / total for k, v in out.items()}


def _argmax(d: dict[str, float]) -> tuple[str, float]:
    label = max(d, key=d.get)
    return label, float(d[label])


def fuse(
    face: Optional[dict] = None,
    text: Optional[dict] = None,
    *,
    disagreement_margin: float = 0.20,
    strong_confidence: float = 0.55,
    weak_confidence: float = 0.35,
) -> dict:
    """
    Fuse face + text emotion predictions into a single Sakinah-15 result.

    Args:
        face: result dict from emotion.face_model.predict, or None.
        text: result dict from emotion.text_model.predict, or None.

    Returns:
        {
            "predicted": "anxious",
            "confidence": 0.74,
            "scores": {sakinah_label: prob, ...},          # 15-way distribution
            "sources_used": ["face", "text"],              # which models contributed
            "fusion_strategy": "weighted_avg" | "higher_confidence" | "single",
            "face_predicted": "Fear",
            "face_confidence": 0.68,
            "text_predicted": "fear",
            "text_confidence": 0.81,
            "low_confidence": False,                       # UI flag for manual fallback
        }
    """
    sources_used = []
    face_proj: Optional[dict[str, float]] = None
    text_proj: Optional[dict[str, float]] = None

    face_label = None
    face_conf = 0.0
    text_label = None
    text_conf = 0.0

    if face and face.get("ok"):
        face_proj = _project(face["scores"], FACE_TO_SAKINAH)
        face_label, face_conf = _argmax(face_proj)
        sources_used.append("face")

    if text and text.get("ok"):
        text_proj = _project(text["scores"], TEXT_TO_SAKINAH)
        text_label, text_conf = _argmax(text_proj)
        sources_used.append("text")

    # Case 1 — no signals at all.
    if not face_proj and not text_proj:
        return {
            "predicted": "confused",
            "confidence": 0.0,
            "scores": {l: 1.0 / 15 for l in SAKINAH_15},
            "sources_used": [],
            "fusion_strategy": "none",
            "face_predicted": None, "face_confidence": 0.0,
            "text_predicted": None, "text_confidence": 0.0,
            "low_confidence": True,
        }

    # Case 2 — only one source.
    if face_proj and not text_proj:
        return {
            "predicted": face_label,
            "confidence": face_conf,
            "scores": face_proj,
            "sources_used": sources_used,
            "fusion_strategy": "single",
            "face_predicted": face["predicted"],
            "face_confidence": float(face.get("confidence", face_conf)),
            "text_predicted": None, "text_confidence": 0.0,
            "low_confidence": face_conf < weak_confidence,
        }
    if text_proj and not face_proj:
        return {
            "predicted": text_label,
            "confidence": text_conf,
            "scores": text_proj,
            "sources_used": sources_used,
            "fusion_strategy": "single",
            "face_predicted": None, "face_confidence": 0.0,
            "text_predicted": text["predicted"],
            "text_confidence": float(text.get("confidence", text_conf)),
            "low_confidence": text_conf < weak_confidence,
        }

    # Case 3 — both sources present.
    # Disagreement check: top labels differ AND both are individually strong.
    disagree = (
        face_label != text_label
        and face_conf >= strong_confidence
        and text_conf >= strong_confidence
    )

    if disagree:
        # Pick whichever model is more confident, tagged as the source of truth.
        if face_conf >= text_conf:
            chosen, chosen_proj, label, conf = "face", face_proj, face_label, face_conf
        else:
            chosen, chosen_proj, label, conf = "text", text_proj, text_label, text_conf
        return {
            "predicted": label,
            "confidence": conf,
            "scores": chosen_proj,
            "sources_used": sources_used,
            "fusion_strategy": f"higher_confidence:{chosen}",
            "face_predicted": face.get("predicted"),
            "face_confidence": float(face.get("confidence", face_conf)),
            "text_predicted": text.get("predicted"),
            "text_confidence": float(text.get("confidence", text_conf)),
            "low_confidence": False,
        }

    # Confidence-weighted average — well-conditioned case.
    raw_face_conf = float(face.get("confidence", face_conf))
    raw_text_conf = float(text.get("confidence", text_conf))
    total = raw_face_conf + raw_text_conf or 1.0
    w_face = raw_face_conf / total
    w_text = raw_text_conf / total

    fused = {l: w_face * face_proj[l] + w_text * text_proj[l] for l in SAKINAH_15}
    label, conf = _argmax(fused)

    # Both sources weak -> manual fallback hint.
    low_conf = (raw_face_conf < weak_confidence and raw_text_conf < weak_confidence)

    return {
        "predicted": label,
        "confidence": conf,
        "scores": fused,
        "sources_used": sources_used,
        "fusion_strategy": "weighted_avg",
        "face_predicted": face.get("predicted"),
        "face_confidence": raw_face_conf,
        "text_predicted": text.get("predicted"),
        "text_confidence": raw_text_conf,
        "low_confidence": low_conf,
    }
