import os
import json
import httpx
from fastapi import APIRouter, HTTPException
from dotenv import load_dotenv
from rag import search_stories
from models import GuidanceRequest

load_dotenv()

router = APIRouter(prefix="/api", tags=["guidance"])

GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"

if "gsk_" in GROQ_API_KEY:
    print("Groq API Key loaded!")
else:
    print("WARNING: GROQ_API_KEY not set. AI guidance will use fallback mode.")


# --- Supported Emotions ---
SUPPORTED_EMOTIONS = [
    "happy", "sad", "anxious", "angry", "confused",
    "grateful", "lonely", "stressed", "fearful", "guilty",
    "hopeless", "overwhelmed", "rejected", "embarrassed", "lost"
]

# --- Crisis keywords — checked before RAG/Groq ---
CRISIS_KEYWORDS = [
    "kill myself", "end my life", "want to die", "suicide", "suicidal",
    "self-harm", "self harm", "hurt myself", "cut myself", "no reason to live",
    "can't go on", "cannot go on", "don't want to live", "do not want to live"
]

CRISIS_RESPONSE = {
    "crisis": True,
    "crisis_message": (
        "I can hear that you're going through something very painful right now. "
        "Please know you are not alone — Allah (SWT) is always near to those who call upon Him. "
        "Your life has value and meaning. Please reach out for immediate support:\n\n"
        "• Umang Pakistan Helpline: 0317-4288665 (24/7)\n"
        "• Rozan Counselling: 051-2890505\n"
        "• Talk to someone you trust right now.\n\n"
        "The guidance below is still here for you, but please seek help first."
    )
}

# --- System Prompt ---
SYSTEM_PROMPT = """You are Sakinah, a compassionate Islamic emotional wellness guide. Your role is to connect a user's emotional state with relevant stories from the Seerah (life of Prophet Muhammad, peace be upon him) to provide comfort, perspective, and practical guidance.

RULES:
1. You will receive the user's emotion, their journal entry, and one or more retrieved Seerah stories.
2. Your response MUST be grounded in the provided Seerah stories. Do NOT invent stories or details not present in the provided context.
3. ONLY use Seerah stories as your primary source. Do NOT quote Quran verses or Hadith as primary sources. You may briefly reference them ONLY if they naturally appear within the provided Seerah story.
4. Be warm, empathetic, and gentle in tone. Acknowledge the user's feelings before offering guidance.
5. Connect the user's specific situation (from their journal entry) to the Seerah story naturally.
6. Extract practical, actionable advice from the story.
7. End with a short, relevant dua (supplication) in English transliteration with its meaning.
8. Keep the seerah_connection around 150-250 words.

OUTPUT JSON FORMAT:
{
    "seerah_connection": "A 2-3 paragraph personalized narrative connecting the user's emotion and journal entry to the Seerah story. Start by acknowledging their feeling, then tell the relevant part of the story, then draw the parallel.",
    "lessons": ["Lesson 1 drawn from the story", "Lesson 2", "Lesson 3"],
    "practical_advice": ["Specific actionable advice 1", "Advice 2", "Advice 3"],
    "dua": "A short relevant dua in English transliteration with meaning"
}

IMPORTANT:
- If the journal entry contains harmful or self-harm content, respond with empathy and gently encourage seeking professional help, while still providing comfort from the Seerah.
- Never dismiss or minimize the user's emotions.
- The tone should feel like a wise, caring older sibling who knows the Seerah deeply.
- Respond ONLY with valid JSON. No extra text before or after the JSON."""


def _detect_crisis(text: str) -> bool:
    lower = text.lower()
    return any(kw in lower for kw in CRISIS_KEYWORDS)


# ============================
#  1. GET GUIDANCE (CORE ENDPOINT)
# ============================
@router.post("/guidance")
async def get_guidance(request: GuidanceRequest):
    emotion = request.emotion.lower().strip()
    if emotion not in SUPPORTED_EMOTIONS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported emotion: '{emotion}'. Supported: {SUPPORTED_EMOTIONS}"
        )

    # Crisis check — before any RAG/LLM work
    is_crisis = _detect_crisis(request.journal_entry)

    # RAG retrieval
    stories = search_stories(request.journal_entry, emotion)
    if not stories:
        raise HTTPException(
            status_code=404,
            detail="No relevant stories found. Please try rephrasing your journal entry."
        )

    best_story = stories[0]

    # Build LLM context from top 2 stories
    stories_context = ""
    for i, story in enumerate(stories[:2]):
        stories_context += (
            f"\n--- Story {i+1}: {story.get('title', '')} ---\n"
            f"Period: {story.get('period', '')}\n"
            f"Summary: {story.get('summary', '')}\n"
            f"Full Story: {story.get('story', '')}\n"
            f"Lessons: {', '.join(story.get('lessons', []))}\n"
            f"Practical Advice: {', '.join(story.get('practical_advice', []))}\n"
        )

    user_prompt = (
        f"User's Emotion: {emotion}\n"
        f"User's Journal Entry: \"{request.journal_entry}\"\n\n"
        f"Retrieved Seerah Stories:\n{stories_context}\n\n"
        f"Based on the above, generate personalized emotional guidance connecting the user's situation to the Seerah story.\n"
        f"Response (JSON):"
    )

    # Call Groq asynchronously
    ai_fallback = False
    ai_result = None

    if "gsk_" in GROQ_API_KEY:
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.post(
                    GROQ_URL,
                    headers={
                        "Authorization": f"Bearer {GROQ_API_KEY}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "model": "llama-3.3-70b-versatile",
                        "messages": [
                            {"role": "system", "content": SYSTEM_PROMPT},
                            {"role": "user", "content": user_prompt}
                        ],
                        "temperature": 0.7,
                        "response_format": {"type": "json_object"}
                    }
                )

            if response.status_code == 200:
                content = response.json()["choices"][0]["message"]["content"]
                ai_result = json.loads(content)
            else:
                print(f"Groq Error {response.status_code}: {response.text}")
                ai_fallback = True

        except Exception as e:
            print(f"Groq call failed: {e}")
            ai_fallback = True
    else:
        ai_fallback = True

    if ai_result:
        result = {
            "story_title": best_story.get("title", ""),
            "story_period": best_story.get("period", ""),
            "story_summary": best_story.get("summary", ""),
            "seerah_connection": ai_result.get("seerah_connection", ""),
            "lessons": ai_result.get("lessons", best_story.get("lessons", [])),
            "practical_advice": ai_result.get("practical_advice", best_story.get("practical_advice", [])),
            "dua": ai_result.get("dua", "May Allah ease your heart and grant you peace."),
            "emotion": emotion,
            "ai_fallback": False
        }
    else:
        result = {
            "story_title": best_story.get("title", ""),
            "story_period": best_story.get("period", ""),
            "story_summary": best_story.get("summary", ""),
            "seerah_connection": best_story.get("story", ""),
            "lessons": best_story.get("lessons", []),
            "practical_advice": best_story.get("practical_advice", []),
            "dua": "May Allah ease your heart and grant you peace. (Allahumma yassir wa la tu'assir)",
            "emotion": emotion,
            "ai_fallback": True
        }

    # Attach crisis info if detected
    if is_crisis:
        result.update(CRISIS_RESPONSE)

    return result


# ============================
#  2. GET SUPPORTED EMOTIONS
# ============================
@router.get("/emotions")
def get_emotions():
    return {"emotions": SUPPORTED_EMOTIONS}


# ============================
#  3. HEALTH CHECK
# ============================
@router.get("/health")
def health_check():
    return {"status": "ok", "service": "sakinah-guidance-api"}
