"""
Firebase Auth verification for the FastAPI backend.

Codex review (2026-05-02) flagged that /api/admin/* was open to the
public — anyone who reached the backend could create, edit, or delete
Seerah stories. This module provides a FastAPI dependency that verifies
the caller's Firebase ID token AND checks the `admin` custom claim.

Wire it into a router with:

    from auth import require_admin
    @router.post("/stories", dependencies=[Depends(require_admin)])
    async def add_story(...):
        ...

Or onto the whole router:

    router = APIRouter(prefix="/api/admin", dependencies=[Depends(require_admin)])

Initialisation:
    The Firebase Admin SDK needs a service-account JSON. We try, in
    order:
      1. GOOGLE_APPLICATION_CREDENTIALS env var (standard Google convention)
      2. backend/serviceAccountKey.json (gitignored — local dev)
      3. application default credentials (works on GCP / Cloud Run)
    If none of those work, we raise on first /api/admin/* call rather
    than at startup — that way the rest of the API still serves.

Granting admin:
    Once: from a trusted shell run something like
        from firebase_admin import auth
        auth.set_custom_user_claims(UID, { "admin": True })
    The next ID token the user gets will carry the admin claim.
"""
from __future__ import annotations

import os
from functools import lru_cache
from typing import Optional

from fastapi import Depends, Header, HTTPException, status

# Defer firebase_admin import to first use — keeps cold-start light when
# admin endpoints aren't being called (e.g. running the emotion API
# locally without a service account).
_firebase_initialised = False
_firebase_init_error: Optional[str] = None


def _init_firebase_admin() -> None:
    global _firebase_initialised, _firebase_init_error
    if _firebase_initialised:
        return

    try:
        import firebase_admin  # type: ignore
        from firebase_admin import credentials  # type: ignore

        if firebase_admin._apps:  # already initialised by something else
            _firebase_initialised = True
            return

        # Try explicit env-var path first.
        cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
        if not cred_path:
            local = os.path.join(
                os.path.dirname(__file__), "serviceAccountKey.json"
            )
            if os.path.isfile(local):
                cred_path = local

        if cred_path and os.path.isfile(cred_path):
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
        else:
            # Application default credentials (works on GCP / Cloud Run /
            # locally if `gcloud auth application-default login` was run).
            firebase_admin.initialize_app()

        _firebase_initialised = True
    except Exception as e:
        _firebase_init_error = str(e)
        # Re-raise on the actual call below; don't crash startup.


@lru_cache(maxsize=1)
def _bootstrap_once() -> None:
    """Init wrapped in lru_cache so the firebase_admin.initialize_app()
    side effect happens exactly once per process even if the dependency
    is wired into many routes."""
    _init_firebase_admin()


def require_admin(
    authorization: Optional[str] = Header(None),
) -> dict:
    """
    FastAPI dependency. Returns the decoded ID token (a dict) on success;
    raises 401/403 on failure.

    Expected header:  Authorization: Bearer <firebase-id-token>
    """
    _bootstrap_once()

    if _firebase_init_error and not _firebase_initialised:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "Admin auth is not configured on this server. "
                "Set GOOGLE_APPLICATION_CREDENTIALS or place "
                "serviceAccountKey.json in the backend directory."
            ),
        )

    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    id_token = authorization.split(" ", 1)[1].strip()
    if not id_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Empty bearer token.",
        )

    try:
        from firebase_admin import auth as fb_auth  # type: ignore
        decoded = fb_auth.verify_id_token(id_token, check_revoked=False)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid ID token: {type(e).__name__}",
        )

    if not decoded.get("admin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin privilege required for this operation.",
        )

    return decoded


# Convenience: same idea but doesn't require the admin claim — verifies
# the user is signed in. Future endpoints (e.g. user-scoped journal
# history if we ever serve that from the backend) can use this.
def require_user(
    authorization: Optional[str] = Header(None),
) -> dict:
    _bootstrap_once()

    if _firebase_init_error and not _firebase_initialised:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Auth is not configured on this server.",
        )

    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header.",
        )

    id_token = authorization.split(" ", 1)[1].strip()
    try:
        from firebase_admin import auth as fb_auth  # type: ignore
        return fb_auth.verify_id_token(id_token, check_revoked=False)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid ID token: {type(e).__name__}",
        )
