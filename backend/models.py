from pydantic import BaseModel


# --- Guidance Request Model ---
class GuidanceRequest(BaseModel):
    journal_entry: str
    emotion: str
