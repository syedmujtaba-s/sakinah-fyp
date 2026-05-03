---
title: Sakinah Backend
emoji: 🌙
colorFrom: green
colorTo: indigo
sdk: docker
pinned: false
license: mit
short_description: Multi-modal emotion detection + Seerah-grounded guidance
---

# Sakinah Backend

FastAPI backend for the Sakinah Emotional Wellness mobile app — final-year-project at COMSATS University Islamabad (Wah Campus). This Space hosts the inference pipeline; the mobile app talks to it over HTTPS.

## What this service does

Receives a journal entry (English or Roman Urdu) and/or a face image, returns:
- A **detected emotion** from a 16-label Sakinah taxonomy
- **Seerah-grounded guidance** retrieved via RAG over a 2,961-story corpus
- A **dua** (supplication) and **practical advice** drawn from the matched story

## Pipeline

| Layer | Model |
|---|---|
| Face emotion | HSEmotion `enet_b2_8` (AffectNet-trained, ONNX) |
| Text emotion | `j-hartmann/emotion-english-distilroberta-base` + Groq Llama-3.3-70b for Roman-Urdu translation |
| Vision LLM fallback | Groq `meta-llama/llama-4-scout-17b-16e-instruct` |
| Embeddings | `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` |
| Vector search | MongoDB Atlas Vector Search |
| Guidance generation | Groq Llama-3.3-70b |

## Required environment variables

Set these in **Settings → Variables and secrets** on the Space:

| Variable | Required | Purpose |
|---|---|---|
| `GROQ_API_KEY` | yes | Guidance + vision LLM + Roman-Urdu translation |
| `MONGO_URI` | yes | Atlas connection string |
| `DB_NAME` | yes | Mongo database name (e.g. `sakinah`) |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | for admin | Raw JSON contents of the Firebase Admin SDK service account. Required for `/api/admin/*`; `/api/emotion/*` and `/api/guidance` work without it |
| `SAKINAH_VISION_MODEL` | optional | Override the vision LLM model name; defaults to llama-4-scout |
| `SAKINAH_VISION_FALLBACK_THRESHOLD` | optional | Face confidence threshold below which vision LLM fires; default 0.65 |

## Endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/api/emotion/detect` | none | Multipart: optional `image` JPEG, optional `journal_text` |
| GET  | `/api/emotion/health` | none | Health + model-load probe |
| POST | `/api/guidance` | none | Body: `{journal_entry, emotion, ...}` → Seerah guidance |
| GET  | `/api/emotions` | none | List of supported emotions |
| GET  | `/api/daily-wisdom` | none | Cached daily Seerah wisdom |
| `/api/admin/*` | **admin** | Story corpus management; Firebase ID token + `admin: true` claim |

## Privacy posture

- Image bytes are processed in memory and discarded; never persisted.
- Logs record text length, not raw journal content.
- Service account keys live in Space env vars, not in the image.

## Local development

See the project [GitHub repo](https://github.com/syedmujtaba-s/sakinah-fyp) — `backend/RUN.TXT` has the local setup commands.

## Authors

Syed Mujtaba Shah ([github](https://github.com/syedmujtaba-s)) and Khushbakht Nawaz, supervised by Mian Muhammad Talha at COMSATS Wah Campus, Session 2022-2026.
