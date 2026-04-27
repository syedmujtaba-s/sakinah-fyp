"""
Face emotion detection using HSEmotion (AffectNet-8 trained, ONNX runtime).

Pipeline:
  1. Decode JPEG/PNG bytes -> RGB numpy array.
  2. Detect the dominant face with OpenCV's Haar cascade. (The Flutter app
     also runs an ML Kit face-quality gate before upload, so this is a
     belt-and-suspenders crop.)
  3. Pad+square the crop to keep aspect ratio (HSEmotion is sensitive to
     non-square inputs).
  4. Run HSEmotion -> 8-class probabilities + valence/arousal scalars.

HSEmotion's 8 emotions follow the AffectNet taxonomy:
    Anger, Contempt, Disgust, Fear, Happiness, Neutral, Sadness, Surprise.
"""
from __future__ import annotations

import io
from typing import Optional

import cv2
import numpy as np
from PIL import Image, ImageOps

# AffectNet-8 label order produced by HSEmotion's `enet_b2_8`.
AFFECTNET_LABELS = [
    "Anger", "Contempt", "Disgust", "Fear",
    "Happiness", "Neutral", "Sadness", "Surprise",
]

# Lazy singletons — first call costs ~2-4s, subsequent calls <300ms on CPU.
_recognizer = None
_face_cascade = None


def _get_recognizer():
    global _recognizer
    if _recognizer is None:
        from hsemotion_onnx.facial_emotions import HSEmotionRecognizer
        print("[face_model] Loading HSEmotion (enet_b2_8)...")
        _recognizer = HSEmotionRecognizer(model_name="enet_b2_8")
        print("[face_model] HSEmotion ready.")
    return _recognizer


def _get_face_cascade():
    global _face_cascade
    if _face_cascade is None:
        cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        _face_cascade = cv2.CascadeClassifier(cascade_path)
        if _face_cascade.empty():
            raise RuntimeError(f"Failed to load Haar cascade at {cascade_path}")
    return _face_cascade


def warmup() -> None:
    """Pre-load both the cascade and HSEmotion. Called from main.py startup."""
    _get_face_cascade()
    _get_recognizer()


def _decode_image(image_bytes: bytes) -> np.ndarray:
    """Decode incoming bytes into an RGB uint8 array, applying EXIF rotation."""
    img = Image.open(io.BytesIO(image_bytes))
    img = ImageOps.exif_transpose(img).convert("RGB")
    return np.array(img)


def _detect_faces(rgb: np.ndarray):
    """Run Haar cascade on a single orientation. Returns list of (x,y,w,h)."""
    cascade = _get_face_cascade()
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    return cascade.detectMultiScale(
        gray, scaleFactor=1.15, minNeighbors=5, minSize=(60, 60)
    )


def _crop_largest_face(rgb: np.ndarray) -> Optional[np.ndarray]:
    """
    Detect faces with Haar cascade; return the largest face crop padded to
    a square. Returns None if no face is detected.

    Phone front cameras often save the JPEG in sensor orientation rather
    than the displayed orientation, so EXIF-transpose alone isn't enough.
    We try the original image first, then fall back to 90°/180°/270°
    rotations and keep the result with the largest face area.
    """
    candidates = []
    for k in (0, 1, 2, 3):
        rotated = np.rot90(rgb, k=k) if k else rgb
        faces = _detect_faces(rotated)
        if len(faces) == 0:
            continue
        x, y, w, h = max(faces, key=lambda r: r[2] * r[3])
        candidates.append((w * h, k, rotated, (x, y, w, h)))
        # Optimization: if we got a clearly large face on the first try,
        # don't bother rotating.
        if k == 0 and w * h > 0.05 * rotated.shape[0] * rotated.shape[1]:
            break

    if not candidates:
        return None

    # Pick the rotation where the largest face was found.
    _, _, rgb, (x, y, w, h) = max(candidates, key=lambda c: c[0])

    # Expand the crop ~20% to include forehead/chin which improves accuracy.
    pad = int(0.20 * max(w, h))
    H, W = rgb.shape[:2]
    x0 = max(0, x - pad)
    y0 = max(0, y - pad)
    x1 = min(W, x + w + pad)
    y1 = min(H, y + h + pad)
    crop = rgb[y0:y1, x0:x1]

    # Square-pad with edge replication so HSEmotion sees a centered face.
    ch, cw = crop.shape[:2]
    side = max(ch, cw)
    top = (side - ch) // 2
    bottom = side - ch - top
    left = (side - cw) // 2
    right = side - cw - left
    crop = cv2.copyMakeBorder(crop, top, bottom, left, right, cv2.BORDER_REPLICATE)
    return crop


def predict(image_bytes: bytes) -> dict:
    """
    Run face emotion detection on a JPEG/PNG byte payload.

    Returns:
        {
            "ok": True,
            "predicted": "Happiness",
            "confidence": 0.91,
            "scores": {"Anger": 0.01, "Contempt": 0.0, ..., "Surprise": 0.02},
            "valence": 0.6,    # if available, else None
            "arousal": 0.4,    # if available, else None
        }

    Or on failure:
        {"ok": False, "error": "no_face_detected" | "decode_failed", "detail": "..."}
    """
    try:
        rgb = _decode_image(image_bytes)
    except Exception as e:
        return {"ok": False, "error": "decode_failed", "detail": str(e)}

    face_crop = _crop_largest_face(rgb)
    if face_crop is None:
        return {"ok": False, "error": "no_face_detected",
                "detail": "Could not locate a face in the image."}

    fer = _get_recognizer()
    # HSEmotion's predict_emotions returns (label, scores_array) when logits=False.
    label, scores_array = fer.predict_emotions(face_crop, logits=False)

    # The library may also expose valence/arousal via predict_multi_emotions
    # on enet models; safe default to None and fill from scores when possible.
    valence, arousal = _try_valence_arousal(fer, face_crop)

    scores = {AFFECTNET_LABELS[i]: float(scores_array[i])
              for i in range(min(len(AFFECTNET_LABELS), len(scores_array)))}
    confidence = float(max(scores.values())) if scores else 0.0

    return {
        "ok": True,
        "predicted": str(label),
        "confidence": confidence,
        "scores": scores,
        "valence": valence,
        "arousal": arousal,
    }


def _try_valence_arousal(fer, face_crop) -> tuple[Optional[float], Optional[float]]:
    """
    Some HSEmotion variants expose continuous valence/arousal regression.
    We try, but never fail if unavailable — these fields are nice-to-have.
    """
    fn = getattr(fer, "predict_emotions", None)
    if fn is None:
        return None, None
    try:
        # Newer versions may return (emotion, scores, valence, arousal) when
        # called with extended kwargs. Older versions don't — we just probe.
        result = fn(face_crop, logits=False)
        if isinstance(result, tuple) and len(result) >= 4:
            return float(result[2]), float(result[3])
    except Exception:
        pass
    return None, None
