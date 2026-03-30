from fastapi import APIRouter
from datetime import datetime, timedelta
from database import stories_collection

router = APIRouter(prefix="/api", tags=["wisdom"])

# Simple in-memory cache — refreshes once per hour
_cache: dict = {"data": None, "expires_at": None}


@router.get("/daily-wisdom")
def get_daily_wisdom():
    now = datetime.now()

    # Return cached result if still fresh
    if _cache["data"] is not None and _cache["expires_at"] and now < _cache["expires_at"]:
        return _cache["data"]

    stories = list(stories_collection.find(
        {},
        {"_id": 0, "title": 1, "period": 1, "summary": 1, "lessons": 1}
    ))

    if not stories:
        result = {
            "lesson": "Every hardship is a doorway to closeness with Allah.",
            "story_title": "Seerah Wisdom",
            "story_period": "",
            "summary": "",
        }
        # Don't cache the empty fallback — retry next call
        return result

    day_of_year = now.timetuple().tm_yday
    story = stories[day_of_year % len(stories)]

    lessons = story.get("lessons", [])
    lesson_index = (day_of_year // len(stories)) % max(len(lessons), 1)
    chosen_lesson = lessons[lesson_index] if lessons else story.get("summary", "")

    result = {
        "lesson": chosen_lesson,
        "story_title": story.get("title", ""),
        "story_period": story.get("period", ""),
        "summary": story.get("summary", ""),
    }

    # Cache for 1 hour
    _cache["data"] = result
    _cache["expires_at"] = now + timedelta(hours=1)

    return result
