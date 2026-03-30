"""
Basic API tests for the Sakinah backend.

Run with:
    pytest test_api.py -v
"""

import pytest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


# ============================
#  1. HEALTH CHECK
# ============================
def test_health():
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_root():
    response = client.get("/")
    assert response.status_code == 200
    assert "msg" in response.json()


# ============================
#  2. EMOTIONS LIST
# ============================
def test_get_emotions():
    response = client.get("/api/emotions")
    assert response.status_code == 200
    data = response.json()
    assert "emotions" in data
    assert "anxious" in data["emotions"]
    assert "sad" in data["emotions"]
    assert len(data["emotions"]) == 15


# ============================
#  3. GUIDANCE — invalid emotion
# ============================
def test_guidance_invalid_emotion():
    response = client.post("/api/guidance", json={
        "journal_entry": "I feel something weird",
        "emotion": "invisible"
    })
    assert response.status_code == 400
    assert "Unsupported emotion" in response.json()["detail"]


# ============================
#  4. GUIDANCE — no stories in DB (empty index)
# ============================
def test_guidance_no_stories():
    with patch("guidance_router.search_stories", return_value=[]):
        response = client.post("/api/guidance", json={
            "journal_entry": "I am feeling very sad today",
            "emotion": "sad"
        })
    assert response.status_code == 404


# ============================
#  5. GUIDANCE — Groq success path
# ============================
MOCK_STORY = {
    "_id": "abc123",
    "title": "The Year of Sorrow",
    "period": "10th Year of Prophethood",
    "summary": "The Prophet lost his wife and uncle.",
    "story": "Full story text here.",
    "lessons": ["Trust in Allah", "Grief is natural"],
    "practical_advice": ["Make dua", "Seek support"],
    "search_score": 0.85,
    "emotions": ["sad"]
}

MOCK_AI_RESPONSE = {
    "seerah_connection": "Your sadness mirrors the Year of Sorrow...",
    "lessons": ["Grief is natural", "Trust Allah"],
    "practical_advice": ["Make dua in sujood", "Talk to someone"],
    "dua": "Allahumma inni as'aluka al-afiyah"
}

def test_guidance_groq_success():
    mock_http_response = MagicMock()
    mock_http_response.status_code = 200
    mock_http_response.json.return_value = {
        "choices": [{"message": {"content": str(MOCK_AI_RESPONSE).replace("'", '"')}}]
    }

    with patch("guidance_router.search_stories", return_value=[MOCK_STORY]):
        with patch("guidance_router.json.loads", return_value=MOCK_AI_RESPONSE):
            # Patch httpx async call
            import httpx
            with patch.object(httpx.AsyncClient, "post", return_value=mock_http_response):
                response = client.post("/api/guidance", json={
                    "journal_entry": "I lost my friend today and feel very sad.",
                    "emotion": "sad"
                })

    assert response.status_code == 200
    data = response.json()
    assert "seerah_connection" in data
    assert "lessons" in data
    assert "practical_advice" in data
    assert "dua" in data
    assert "ai_fallback" in data


# ============================
#  6. GUIDANCE — Groq failure → ai_fallback = True
# ============================
def test_guidance_groq_fallback():
    with patch("guidance_router.search_stories", return_value=[MOCK_STORY]):
        with patch("guidance_router.GROQ_API_KEY", ""):  # No key → triggers fallback
            response = client.post("/api/guidance", json={
                "journal_entry": "I am feeling anxious about exams.",
                "emotion": "anxious"
            })

    assert response.status_code == 200
    data = response.json()
    assert data["ai_fallback"] is True
    assert data["story_title"] == MOCK_STORY["title"]


# ============================
#  7. CRISIS DETECTION
# ============================
def test_guidance_crisis_detected():
    with patch("guidance_router.search_stories", return_value=[MOCK_STORY]):
        with patch("guidance_router.GROQ_API_KEY", ""):
            response = client.post("/api/guidance", json={
                "journal_entry": "I want to kill myself, nothing matters anymore.",
                "emotion": "hopeless"
            })

    assert response.status_code == 200
    data = response.json()
    assert data.get("crisis") is True
    assert "crisis_message" in data
    assert "Umang" in data["crisis_message"]


def test_guidance_no_crisis_false_positive():
    """Normal sad entry should NOT trigger crisis flag."""
    with patch("guidance_router.search_stories", return_value=[MOCK_STORY]):
        with patch("guidance_router.GROQ_API_KEY", ""):
            response = client.post("/api/guidance", json={
                "journal_entry": "I am feeling sad and lonely today.",
                "emotion": "sad"
            })

    assert response.status_code == 200
    data = response.json()
    assert data.get("crisis") is not True


# ============================
#  8. DAILY WISDOM
# ============================
def test_daily_wisdom_no_stories():
    with patch("wisdom_router.stories_collection") as mock_coll:
        mock_coll.find.return_value = []
        # Clear cache first
        import wisdom_router
        wisdom_router._cache["data"] = None
        wisdom_router._cache["expires_at"] = None

        response = client.get("/api/daily-wisdom")

    assert response.status_code == 200
    data = response.json()
    assert "lesson" in data


def test_daily_wisdom_returns_data():
    mock_stories = [
        {"title": "Cave of Thawr", "period": "Hijrah", "summary": "Test summary",
         "lessons": ["Trust in Allah"]}
    ]
    with patch("wisdom_router.stories_collection") as mock_coll:
        mock_coll.find.return_value = mock_stories
        import wisdom_router
        wisdom_router._cache["data"] = None
        wisdom_router._cache["expires_at"] = None

        response = client.get("/api/daily-wisdom")

    assert response.status_code == 200
    data = response.json()
    assert data["story_title"] == "Cave of Thawr"
    assert data["lesson"] == "Trust in Allah"
