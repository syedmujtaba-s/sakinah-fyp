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

# Fast, cheap model for the off-topic pre-flight classifier. We do NOT use
# the same model as guidance (llama-3.3-70b) here — this check needs to be
# sub-300ms so it doesn't bloat every guidance call. 8b-instant is plenty
# for a yes/no decision.
OFFTOPIC_MODEL = "llama-3.1-8b-instant"
OFFTOPIC_REDIRECT_MESSAGE = (
    "Sakinah is here for emotional reflection. Try sharing how you're "
    "feeling — what's been on your heart today?"
)
OFFTOPIC_SUGGESTED_PROMPTS = [
    "I've been feeling anxious about ...",
    "I feel grateful for ...",
    "I'm struggling with ...",
    "Lately I've felt overwhelmed because ...",
]

if "gsk_" in GROQ_API_KEY:
    print("Groq API Key loaded!")
else:
    print("WARNING: GROQ_API_KEY not set. AI guidance will use fallback mode.")


# Imported from the central taxonomy. Codex caught that adding "neutral"
# left admin_router.py validating against the old 15-emotion list while
# this router accepted the new one — single source of truth fixes that.
from emotion.taxonomy import SAKINAH_EMOTIONS as SUPPORTED_EMOTIONS

# --- Crisis keywords — checked before RAG/Groq ---
# Hard signals: any one of these flips the crisis flag regardless of mood.
CRISIS_KEYWORDS = [
    "kill myself", "end my life", "ending my life", "end it all", "take my life",
    "want to die", "suicide", "suicidal",
    "self-harm", "self harm", "hurt myself", "cut myself",
    "no reason to live", "no point living", "not worth living",
    "better off dead", "give up on life",
    "can't go on", "cannot go on", "don't want to live", "do not want to live"
]

# Soft signals: phrases people use when they're in distress but stop short of
# explicit suicide language. We ONLY treat these as crisis when the multi-modal
# pipeline has already classified the user's mood as hopeless/lost/lonely —
# i.e. face + text fusion is showing low valence. This is the "face-augmented
# crisis detection" the plan called for, without needing the raw valence
# scalar on the wire (the emotion label is already a downstream signal of it).
SOFT_DISTRESS_KEYWORDS = [
    "can't take", "cant take", "can't handle", "cant handle",
    "exhausted with life", "broken inside", "feel empty", "feeling empty",
    "no hope", "no point", "tired of everything", "give up",
    "what's the point", "whats the point",
    "alone forever", "everything is dark", "everything feels dark",
    "i'm done", "im done", "completely lost",
]
SOFT_TRIGGER_EMOTIONS = {"hopeless", "lost", "lonely", "sad"}

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
    "dua": "A short relevant dua in English transliteration with meaning",
    "follow_up_questions": [
        "A short question the user might naturally ask next about this story or situation — <= 10 words",
        "A second follow-up question on a different angle",
        "A third follow-up question"
    ]
}

IMPORTANT:
- If the journal entry contains harmful or self-harm content, respond with empathy and gently encourage seeking professional help, while still providing comfort from the Seerah.
- Never dismiss or minimize the user's emotions.
- The tone should feel like a wise, caring older sibling who knows the Seerah deeply.
- follow_up_questions should open a thoughtful next conversation (e.g., "How did the Prophet ﷺ respond after this?" or "What can I read next?"). Each <= 10 words.
- Respond ONLY with valid JSON. No extra text before or after the JSON."""


def _detect_crisis(text: str, emotion: str = "") -> bool:
    """
    Two-tier crisis detection.

    Tier 1 — hard keywords: explicit suicide/self-harm language always wins.
    Tier 2 — soft keywords + face-aware mood gate: phrases like "no point" or
    "i can't take this" only count when the user's *detected emotion* is
    already hopeless/lost/lonely/sad. This catches people whose face + journal
    fusion is screaming distress even when their wording is muted.
    """
    lower = text.lower()
    if any(kw in lower for kw in CRISIS_KEYWORDS):
        return True
    if emotion in SOFT_TRIGGER_EMOTIONS and any(
        kw in lower for kw in SOFT_DISTRESS_KEYWORDS
    ):
        return True
    return False


# In-process cache keyed by stripped+lowercased text. A user often submits
# similar-looking entries while iterating; this avoids paying for the same
# classifier call twice in a session. Cap is small — process restarts clear it.
_OFFTOPIC_CACHE: dict[str, bool] = {}
_OFFTOPIC_CACHE_CAP = 512


async def _detect_off_topic(text: str) -> bool:
    """
    Fast Groq pre-flight that decides whether the journal entry is an
    emotional reflection. Returns True if it looks off-topic (factual
    questions, jokes, unrelated chat).

    Guarantees:
      - empty / very short text -> False (let RAG handle it)
      - Groq failure -> False (fail-open — never block guidance because
        the classifier is down)
      - cache hit -> instant
    """
    stripped = (text or "").strip()
    if len(stripped.split()) < 3:
        return False

    cache_key = stripped.lower()
    if cache_key in _OFFTOPIC_CACHE:
        return _OFFTOPIC_CACHE[cache_key]

    if "gsk_" not in GROQ_API_KEY:
        return False  # no key configured — can't classify, assume on-topic

    prompt = (
        "You are a strict classifier for an emotional wellness app where "
        "users journal feelings. Decide: is the user's text below an "
        "emotional reflection (yes) or off-topic — factual questions, "
        "requests for information, jokes, code, or unrelated chat (no)? "
        "Reply with ONLY the single word 'yes' or 'no'.\n\n"
        f"Text: {stripped}"
    )

    is_offtopic = False
    try:
        async with httpx.AsyncClient(timeout=4.0) as client:
            response = await client.post(
                GROQ_URL,
                headers={
                    "Authorization": f"Bearer {GROQ_API_KEY}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": OFFTOPIC_MODEL,
                    "messages": [{"role": "user", "content": prompt}],
                    "temperature": 0.0,
                    "max_tokens": 5,
                },
            )
        if response.status_code == 200:
            content = response.json()["choices"][0]["message"]["content"]
            first_token = content.strip().lower().split()[0] if content.strip() else ""
            # "no" / "off" / "off-topic" all signal off-topic.
            is_offtopic = first_token.startswith("no") or first_token.startswith("off")
    except Exception as e:
        # Fail-open: a Groq outage must never block the guidance pipeline.
        print(f"[off-topic] classifier failed, defaulting to on-topic: {e}")
        is_offtopic = False

    # Cap-and-evict — keep the cache bounded so it can't OOM a long-lived process.
    if len(_OFFTOPIC_CACHE) >= _OFFTOPIC_CACHE_CAP:
        _OFFTOPIC_CACHE.pop(next(iter(_OFFTOPIC_CACHE)))
    _OFFTOPIC_CACHE[cache_key] = is_offtopic
    return is_offtopic


def _offtopic_response(emotion: str) -> dict:
    """Structured payload the mobile app renders as the redirect dialog."""
    return {
        "off_topic": True,
        "redirect_message": OFFTOPIC_REDIRECT_MESSAGE,
        "suggested_prompts": OFFTOPIC_SUGGESTED_PROMPTS,
        "emotion": emotion,
        "crisis": False,
    }


# Cache for the emotion-mismatch classifier — keyed by "emotion::text".
_MISMATCH_CACHE: dict[str, tuple[bool, str | None]] = {}
_MISMATCH_CACHE_CAP = 512


async def _detect_emotion_mismatch(
    text: str, claimed_emotion: str
) -> tuple[bool, str | None]:
    """
    Fast Groq pre-flight that checks whether the journal text strongly
    contradicts the emotion the user checked in with.

    The check-in emotion is locked at check-in time and the journal text
    written afterwards is never re-analysed — so a user can pick "happy"
    then pour out something clearly sad. Retrieval, the crisis soft-tier,
    and the displayed mood tag all key off that stale label. This catches
    the contradiction and lets the app ask the user which is truer.

    Returns (is_mismatch, suggested_emotion). suggested_emotion is one of
    SAKINAH_EMOTIONS or None.

    Guarantees:
      - text under 4 words -> (False, None): too little signal to judge
      - Groq failure -> (False, None): fail-open, never block guidance
      - suggested == claimed -> treated as no mismatch
    """
    stripped = (text or "").strip()
    if len(stripped.split()) < 4:
        return (False, None)

    cache_key = f"{claimed_emotion}::{stripped.lower()}"
    if cache_key in _MISMATCH_CACHE:
        return _MISMATCH_CACHE[cache_key]

    if "gsk_" not in GROQ_API_KEY:
        return (False, None)

    allowed = ", ".join(sorted(SUPPORTED_EMOTIONS))
    prompt = (
        "A user of an emotional-wellness app checked in feeling "
        f"'{claimed_emotion}'. Here is the reflection they then wrote:\n"
        f'"{stripped}"\n\n'
        "Does the reflection clearly express an emotion that is OPPOSITE "
        f"or very different from '{claimed_emotion}'? Only say yes for a "
        "STRONG, obvious contradiction (e.g. checked in 'happy' but wrote "
        "about grief). Mild nuance is NOT a mismatch.\n"
        f"If yes, pick the single best-fitting label from: {allowed}.\n"
        'Reply ONLY compact JSON: {"mismatch": true|false, '
        '"suggested": "<label>"|null}'
    )

    result: tuple[bool, str | None] = (False, None)
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.post(
                GROQ_URL,
                headers={
                    "Authorization": f"Bearer {GROQ_API_KEY}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": OFFTOPIC_MODEL,
                    "messages": [{"role": "user", "content": prompt}],
                    "temperature": 0.0,
                    "max_tokens": 40,
                    "response_format": {"type": "json_object"},
                },
            )
        if response.status_code == 200:
            content = response.json()["choices"][0]["message"]["content"]
            parsed = json.loads(content)
            is_mismatch = parsed.get("mismatch") is True
            suggested = parsed.get("suggested")
            if isinstance(suggested, str):
                suggested = suggested.strip().lower()
            # Guard: suggestion must be a real taxonomy emotion AND must
            # actually differ from what the user claimed.
            if (
                is_mismatch
                and suggested in SUPPORTED_EMOTIONS
                and suggested != claimed_emotion
            ):
                result = (True, suggested)
    except Exception as e:
        # Fail-open: a Groq hiccup must never block guidance.
        print(f"[mismatch] classifier failed, treating as no mismatch: {e}")
        result = (False, None)

    if len(_MISMATCH_CACHE) >= _MISMATCH_CACHE_CAP:
        _MISMATCH_CACHE.pop(next(iter(_MISMATCH_CACHE)))
    _MISMATCH_CACHE[cache_key] = result
    return result


def _emotion_mismatch_response(claimed: str, suggested: str) -> dict:
    """Structured payload the mobile app renders as the 'which feeling is
    truer?' dialog. The app re-calls /api/guidance with emotion_confirmed
    set, so this check runs at most once per journal submission."""
    return {
        "emotion_mismatch": True,
        "claimed_emotion": claimed,
        "suggested_emotion": suggested,
        "mismatch_message": (
            f"You checked in feeling {claimed}, but your reflection reads "
            f"more like {suggested}. Which feels truer right now?"
        ),
        "crisis": False,
    }


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

    # Crisis check — before any RAG/LLM work. Pass the detected emotion so
    # the soft-signal tier can fire on muted-language distress when the
    # multi-modal pipeline already shows a hopeless/lost mood.
    #
    # Codex review (2026-05-02) caught that the follow-up flow sends an
    # empty `journal_entry` and the crisis check ran on that empty string —
    # so a user asking a follow-up like "what's the point of all this"
    # bypassed the helpline. We now scan the union of journal_entry +
    # followup_question + previous_seerah_connection for crisis cues.
    crisis_haystack = " ".join(
        s for s in (
            request.journal_entry,
            request.followup_question or "",
            request.previous_seerah_connection or "",
        ) if s
    )
    is_crisis = _detect_crisis(crisis_haystack, emotion)

    # Follow-up mode: the user is asking a question about a previous guidance
    # session. Skip RAG (we re-use the previous story) and change the prompt.
    is_followup = (
        request.followup_question is not None
        and request.followup_question.strip() != ""
        and request.previous_story_id is not None
    )

    # Pre-flight checks. Ordering matters:
    #   1. emotion validation (above) — fail-fast invalid emotions
    #   2. crisis check (above) — safety-critical, never bypass
    #   3. off-topic check (HERE) — only if no crisis AND not a follow-up
    #   4. emotion-mismatch check (HERE) — same gating, plus skipped once
    #      the user has confirmed their feeling (emotion_confirmed=True)
    #   5. RAG (below)
    # We do NOT run these on follow-up requests (the thread is already
    # established) or when is_crisis is True (the helpline response wins —
    # a distressed user must never get a redirect or a "pick your mood"
    # dialog instead of help).
    if not is_crisis and not is_followup:
        if await _detect_off_topic(request.journal_entry):
            return _offtopic_response(emotion)

        # Emotion-mismatch: the user's journal text clearly contradicts
        # the emotion they checked in with. We surface this ONCE — the app
        # re-calls with emotion_confirmed=True after the user decides,
        # so this branch can't loop.
        if not request.emotion_confirmed:
            mismatch, suggested = await _detect_emotion_mismatch(
                request.journal_entry, emotion
            )
            if mismatch and suggested:
                return _emotion_mismatch_response(emotion, suggested)

    if is_followup:
        # Fetch the specific story the user was previously shown
        from bson import ObjectId
        from database import stories_collection as _stories
        try:
            story_doc = _stories.find_one({"_id": ObjectId(request.previous_story_id)})
        except Exception:
            story_doc = None
        if not story_doc:
            raise HTTPException(status_code=404, detail="Previous story not found for follow-up.")
        story_doc["_id"] = str(story_doc["_id"])
        stories = [story_doc]
    else:
        # RAG retrieval — honoring any stories the user has already tried and flagged as unhelpful
        stories = search_stories(
            request.journal_entry,
            emotion,
            exclude_story_ids=request.exclude_story_ids,
        )
        if not stories:
            raise HTTPException(
                status_code=404,
                detail="No relevant stories found. Please try rephrasing your journal entry."
            )

    best_story = stories[0]

    # Build LLM context
    if is_followup:
        stories_context = (
            f"\n--- Story: {best_story.get('title', '')} ---\n"
            f"Period: {best_story.get('period', '')}\n"
            f"Summary: {best_story.get('summary', '')}\n"
            f"Full Story: {best_story.get('story', '')}\n"
            f"Lessons: {', '.join(best_story.get('lessons', []))}\n"
            f"Practical Advice: {', '.join(best_story.get('practical_advice', []))}\n"
        )
        user_prompt = (
            f"The user previously reflected (Emotion: {emotion}) and received guidance grounded in this Seerah story.\n"
            f"Previous guidance seerah_connection:\n\"\"\"\n{request.previous_seerah_connection or ''}\n\"\"\"\n\n"
            f"Seerah story context:\n{stories_context}\n\n"
            f"Now the user is asking a follow-up question: \"{request.followup_question}\"\n\n"
            f"Answer the follow-up by staying grounded in this same story and the previous guidance. "
            f"Do NOT repeat the earlier seerah_connection verbatim — go deeper, draw out the specific detail the user asked about.\n"
            f"Response (JSON in the same schema as before — follow_up_questions should propose further deeper questions):"
        )
    else:
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

    # Fallback follow-up suggestions if the LLM doesn't provide any
    _default_followups = [
        "How did the Prophet ﷺ respond next?",
        "What did the companions learn from this?",
        "What dua did he ﷺ make in this moment?",
    ]

    if ai_result:
        result = {
            "story_id": best_story.get("_id", ""),
            "story_title": best_story.get("title", ""),
            "story_period": best_story.get("period", ""),
            "story_summary": best_story.get("summary", ""),
            "story": best_story.get("story", ""),
            "seerah_connection": ai_result.get("seerah_connection", ""),
            "lessons": ai_result.get("lessons", best_story.get("lessons", [])),
            "practical_advice": ai_result.get("practical_advice", best_story.get("practical_advice", [])),
            "dua": ai_result.get("dua", "May Allah ease your heart and grant you peace."),
            "follow_up_questions": ai_result.get("follow_up_questions", _default_followups),
            "emotion": emotion,
            "ai_fallback": False,
            "is_followup": is_followup,
        }
    else:
        result = {
            "story_id": best_story.get("_id", ""),
            "story_title": best_story.get("title", ""),
            "story_period": best_story.get("period", ""),
            "story_summary": best_story.get("summary", ""),
            "story": best_story.get("story", ""),
            "seerah_connection": best_story.get("story", ""),
            "lessons": best_story.get("lessons", []),
            "practical_advice": best_story.get("practical_advice", []),
            "dua": "May Allah ease your heart and grant you peace. (Allahumma yassir wa la tu'assir)",
            "follow_up_questions": _default_followups,
            "emotion": emotion,
            "ai_fallback": True,
            "is_followup": is_followup,
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
