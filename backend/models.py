from pydantic import BaseModel, Field


# --- Guidance Request Model ---
class GuidanceRequest(BaseModel):
    journal_entry: str
    emotion: str
    # Optional: stories the user has already tried whose advice didn't help.
    # The RAG retrieval filters these out before scoring, so the user gets a
    # different story on retry.
    exclude_story_ids: list[str] = Field(default_factory=list)
