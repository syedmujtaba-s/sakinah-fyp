from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="Sakinah Emotional Wellness Backend", version="1.0.0")

# ==========================================
#  MIDDLEWARE
# ==========================================
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,   # Must be False when allow_origins=["*"] per CORS spec
    allow_methods=["*"],
    allow_headers=["*"],
)

# ==========================================
#  ROUTERS
# ==========================================
from guidance_router import router as guidance_router
from wisdom_router import router as wisdom_router
from admin_router import router as admin_router
from emotion_router import router as emotion_router

app.include_router(guidance_router)
app.include_router(wisdom_router)
app.include_router(admin_router)
app.include_router(emotion_router)


# ==========================================
#  STARTUP — auto-ingest & sync index, warm ML models
# ==========================================
@app.on_event("startup")
def startup_tasks():
    from rag import ingest_from_data_folder, sync_new_stories
    ingest_from_data_folder()   # Load any new .jsonl files from data/stories/
    sync_new_stories()          # Index any unindexed stories

    # Warm the emotion-detection models in a background thread so the first
    # /api/emotion/detect request doesn't pay the 3-5s model-load cost.
    import threading
    def _warm():
        try:
            from emotion import face_model, text_model
            face_model.warmup()
            text_model.warmup()
        except Exception as e:
            print(f"[startup] Emotion model warmup failed (non-fatal): {e}")
    threading.Thread(target=_warm, daemon=True).start()


@app.get("/")
def home():
    return {"msg": "Sakinah backend running"}
