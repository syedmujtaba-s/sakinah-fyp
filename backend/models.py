from pydantic import BaseModel, Field


# --- Emotion Detection Response ---
class EmotionDetectionResponse(BaseModel):
    predicted_emotion: str                    # one of Sakinah's 15
    confidence: float
    scores: dict[str, float]                  # full 15-way distribution
    sources_used: list[str]                   # ["face"], ["text"], or both
    fusion_strategy: str                      # "weighted_avg" | "single" | "higher_confidence:face" | ...
    low_confidence: bool                      # UI flag — show manual picker
    # Per-modality breakdown (nullable when that modality wasn't used).
    face_predicted: str | None = None
    face_confidence: float = 0.0
    valence: float | None = None
    arousal: float | None = None
    text_predicted: str | None = None
    text_confidence: float = 0.0
    text_translated: bool = False


# --- Guidance Request Model ---
class GuidanceRequest(BaseModel):
    journal_entry: str
    emotion: str
    # Optional: stories the user has already tried whose advice didn't help.
    # The RAG retrieval filters these out before scoring, so the user gets a
    # different story on retry.
    exclude_story_ids: list[str] = Field(default_factory=list)
    # Optional: a short follow-up question asked after a previous guidance response.
    # When present, the prompt switches to conversational mode and the LLM
    # answers the follow-up grounded in the previously surfaced story.
    followup_question: str | None = None
    # Optional: the previous seerah_connection text so the LLM knows what it
    # already told the user; avoids repetition and grounds the follow-up.
    previous_seerah_connection: str | None = None
    # Optional: the previous story ID; we re-use the same story for follow-ups
    # rather than doing a fresh RAG retrieval (same thread of conversation).
    previous_story_id: str | None = None
