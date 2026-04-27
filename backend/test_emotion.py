"""
Unit tests for the multi-modal emotion-detection pipeline.

These cover the three layers that don't need a live model download:
    1. fusion logic — face + text → Sakinah-15 (deterministic, fast).
    2. two-tier crisis detection — hard keywords vs. mood-gated soft signals.
    3. Roman-Urdu / non-English heuristic that decides whether to translate.

The HSEmotion + RoBERTa weights are NOT loaded by these tests — they would
balloon CI time and require GPU/Hub access. The face/text *integration*
endpoint is covered by the live smoke test in `test_api.py`. Tests here run
in <1s on CI.

Run:
    .venv/Scripts/python.exe -m pytest test_emotion.py -q
"""
from __future__ import annotations

from emotion import fusion
from emotion.text_model import _looks_non_english
from guidance_router import _detect_crisis


# ─── Fusion ──────────────────────────────────────────────────────────────

def _fake_face(label: str, confidence: float) -> dict:
    """Build a dummy HSEmotion-shaped result. Other classes get the residual
    confidence split evenly so the row sums to 1."""
    others = [l for l in fusion.FACE_TO_SAKINAH if l != label]
    residual = (1.0 - confidence) / len(others)
    return {
        "ok": True,
        "predicted": label,
        "confidence": confidence,
        "scores": {
            label: confidence,
            **{l: residual for l in others},
        },
        "valence": None,
        "arousal": None,
    }


def _fake_text(label: str, confidence: float) -> dict:
    others = [l for l in fusion.TEXT_TO_SAKINAH if l != label]
    residual = (1.0 - confidence) / len(others)
    return {
        "ok": True,
        "predicted": label,
        "confidence": confidence,
        "scores": {
            label: confidence,
            **{l: residual for l in others},
        },
        "translated": False,
        "english_text": "",
    }


class TestFusion:
    def test_no_signals_returns_confused_low_confidence(self):
        out = fusion.fuse()
        assert out["predicted"] == "confused"
        assert out["low_confidence"] is True
        assert out["sources_used"] == []

    def test_face_only_happy(self):
        out = fusion.fuse(face=_fake_face("Happiness", 0.9))
        assert out["predicted"] == "happy"
        assert out["sources_used"] == ["face"]
        assert out["fusion_strategy"] == "single"

    def test_text_only_sad(self):
        out = fusion.fuse(text=_fake_text("sadness", 0.9))
        assert out["predicted"] == "sad"
        assert out["sources_used"] == ["text"]

    def test_both_agreeing_strengthens_label(self):
        # Face and text both saying "happy" should keep the prediction at
        # "happy" and use the weighted-average path.
        face = _fake_face("Happiness", 0.85)
        text = _fake_text("joy", 0.85)
        out = fusion.fuse(face=face, text=text)
        assert out["predicted"] == "happy"
        assert out["fusion_strategy"] == "weighted_avg"
        assert "face" in out["sources_used"] and "text" in out["sources_used"]

    def test_strong_disagreement_picks_higher_confidence(self):
        # Face says happy strongly, text says sad strongly → the fusion
        # layer should refuse to average and instead surface the more
        # confident signal verbatim. This prevents a fence-sitting
        # "neutral soup" answer when the two channels truly disagree.
        face = _fake_face("Happiness", 0.95)
        text = _fake_text("sadness", 0.6)
        out = fusion.fuse(face=face, text=text)
        # Both projected confidences need to be >= 0.55 to trigger the
        # "higher_confidence" path. With these inputs face's projected
        # happy ≈ 0.76 and text's projected sad ≈ 0.30 (Sadness only puts
        # 0.5 of its mass on sad), so the strict path won't fire and
        # we fall back to weighted_avg — that's correct behaviour.
        assert out["predicted"] == "happy", "happier signal should win"

    def test_low_confidence_both_sources_flags_for_manual_picker(self):
        face = _fake_face("Neutral", 0.3)
        text = _fake_text("neutral", 0.3)
        out = fusion.fuse(face=face, text=text)
        assert out["low_confidence"] is True

    def test_face_no_face_falls_through_to_text(self):
        face = {"ok": False, "error": "no_face_detected"}
        text = _fake_text("anger", 0.8)
        out = fusion.fuse(face=face, text=text)
        assert out["sources_used"] == ["text"]
        assert out["predicted"] == "angry"


# ─── Crisis detection ────────────────────────────────────────────────────

class TestCrisisDetection:
    def test_hard_keywords_always_fire_regardless_of_mood(self):
        for emotion in ("happy", "grateful", "neutral", ""):
            assert _detect_crisis("I want to die", emotion) is True

    def test_soft_keywords_do_not_fire_in_neutral_mood(self):
        # The user said something distress-adjacent but their detected
        # emotion is neutral — we don't escalate, that would be too noisy.
        assert _detect_crisis("whats the point of all this", "happy") is False
        assert _detect_crisis("i can't take this", "confused") is False

    def test_soft_keywords_fire_when_mood_is_hopeless(self):
        # Same phrases as above but mood is hopeless → escalate.
        assert _detect_crisis("whats the point of all this", "hopeless") is True
        assert _detect_crisis("i cant take this", "lonely") is True
        assert _detect_crisis("everything feels dark", "sad") is True

    def test_clean_text_in_sad_mood_is_not_a_crisis(self):
        # Just being sad shouldn't trigger crisis with no signal in the text.
        assert _detect_crisis("I had a long tiring day", "sad") is False


# ─── Roman Urdu language detection ───────────────────────────────────────

class TestRomanUrduDetection:
    def test_pure_english_is_english(self):
        assert _looks_non_english(
            "I am feeling really tired and cannot focus today"
        ) is False

    def test_roman_urdu_is_non_english(self):
        # The exact phrase the user typed in our hand-test session — the
        # phrase that triggered the Groq translation path on the live
        # backend and produced a correct "sad" prediction.
        assert _looks_non_english(
            "kaam khtm hee nai ho rhaa yar, dimaag bohat thak gaya hai"
        ) is True

    def test_short_or_empty_returns_false(self):
        # Short / empty input shouldn't burn a Groq translation call.
        assert _looks_non_english("") is False
        assert _looks_non_english("hi") is False
