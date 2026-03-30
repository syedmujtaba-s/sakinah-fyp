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

app.include_router(guidance_router)
app.include_router(wisdom_router)

@app.get("/")
def home():
    return {"msg": "Sakinah backend running"}
