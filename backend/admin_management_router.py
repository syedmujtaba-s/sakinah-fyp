"""
Super-admin endpoints for in-panel admin management.

These let a super-admin (custom claim `superAdmin: true`) grant or revoke
the `admin` claim on other Firebase users from the deployed admin panel
UI — no terminal required.

The bootstrap super-admin is set via `grant_admin.py grant-super <email>`
on the developer's laptop. After that, ongoing admin management happens
through this router.

Mounted at /api/admin/admins. Router-level dependency is `require_super_admin`,
so EVERY route here requires both the admin and superAdmin claims —
defence-in-depth on top of the per-endpoint logic.
"""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from auth import require_super_admin

router = APIRouter(
    prefix="/api/admin/admins",
    tags=["admin-management"],
    dependencies=[Depends(require_super_admin)],
)


# ============================
#  Pydantic models
# ============================
class GrantAdminRequest(BaseModel):
    email: str


class AdminRow(BaseModel):
    email: Optional[str]
    uid: str
    isSuperAdmin: bool


# ============================
#  Helpers
# ============================
def _normalise_email(email: str) -> str:
    return email.strip().lower()


def _claims_for(user) -> dict:
    """Defensive copy of user.custom_claims so we never mutate the SDK
    object's internal dict. Mirrors the pattern in grant_admin.py."""
    return dict(user.custom_claims or {})


# ============================
#  GET /  — list all admins
# ============================
@router.get("")
async def list_admins(_=Depends(require_super_admin)):
    """List every Firebase user who currently has admin: true.

    Paginates through all users (Firebase returns up to 1000 per page).
    Returns email, uid, and whether they're a super-admin so the UI can
    show a "Super Admin" badge and hide the Revoke button on those rows.
    """
    from firebase_admin import auth as fb_auth

    admins: list[dict] = []
    page = fb_auth.list_users()
    seen = 0
    HARD_CAP = 5000  # cheap insurance against runaway accounts
    while page and seen < HARD_CAP:
        for user in page.users:
            seen += 1
            claims = user.custom_claims or {}
            if claims.get("admin"):
                admins.append({
                    "email": user.email,
                    "uid": user.uid,
                    "isSuperAdmin": bool(claims.get("superAdmin")),
                })
        page = page.get_next_page()

    return {
        "count": len(admins),
        "admins": admins,
        "scanned": seen,
        "truncated": seen >= HARD_CAP,
    }


# ============================
#  POST /  — grant admin to a user (by email)
# ============================
@router.post("")
async def grant_admin(body: GrantAdminRequest, _=Depends(require_super_admin)):
    """Grant the admin claim to an existing Firebase user, looked up by email.

    The user MUST already exist in Firebase Auth — they have to sign up
    in the mobile app (or the admin panel sign-in screen using a real
    Firebase Auth flow) before they can be promoted.

    Idempotent: if they're already an admin, returns 200 with a friendly
    message rather than 409 — keeps the UI happy on accidental double-clicks.
    """
    from firebase_admin import auth as fb_auth

    email = _normalise_email(body.email)
    try:
        user = fb_auth.get_user_by_email(email)
    except fb_auth.UserNotFoundError:
        raise HTTPException(
            status_code=404,
            detail=(
                f"No Firebase user with email '{email}'. They must sign up "
                f"in the mobile app first, then be promoted from here."
            ),
        )

    claims = _claims_for(user)
    already_admin = bool(claims.get("admin"))
    if already_admin:
        return {
            "message": f"{email} is already an admin.",
            "email": email,
            "uid": user.uid,
            "alreadyAdmin": True,
        }

    claims["admin"] = True
    fb_auth.set_custom_user_claims(user.uid, claims)
    return {
        "message": (
            f"Granted admin to {email}. They must sign out and back in "
            f"to the admin panel for the new claim to take effect."
        ),
        "email": email,
        "uid": user.uid,
        "alreadyAdmin": False,
    }


# ============================
#  DELETE /{email}  — revoke admin claim
# ============================
@router.delete("/{email}")
async def revoke_admin(email: str, requester=Depends(require_super_admin)):
    """Remove the admin claim from a user (preserves all other claims).

    Hard guards:
      1. Cannot revoke yourself — server-side check against the requester's
         email from the verified ID token. Prevents accidental lockout.
      2. Cannot revoke another super-admin via the UI. They must be demoted
         via `grant_admin.py revoke-super` from the developer terminal.
         This stops one super-admin from removing peers through the panel.
    """
    from firebase_admin import auth as fb_auth

    target_email = _normalise_email(email)
    requester_email = _normalise_email(requester.get("email") or "")

    if target_email and target_email == requester_email:
        raise HTTPException(
            status_code=400,
            detail=(
                "You cannot revoke your own admin privilege from the panel. "
                "Ask another super-admin or use the terminal script."
            ),
        )

    try:
        user = fb_auth.get_user_by_email(target_email)
    except fb_auth.UserNotFoundError:
        raise HTTPException(
            status_code=404,
            detail=f"No Firebase user with email '{target_email}'.",
        )

    claims = _claims_for(user)

    if claims.get("superAdmin"):
        raise HTTPException(
            status_code=403,
            detail=(
                "Super-admins cannot be demoted from the panel. Use "
                "`grant_admin.py revoke-super <email>` from the terminal."
            ),
        )

    if not claims.get("admin"):
        return {
            "message": f"{target_email} was not an admin — nothing to do.",
            "email": target_email,
            "uid": user.uid,
        }

    claims.pop("admin", None)
    fb_auth.set_custom_user_claims(user.uid, claims)
    return {
        "message": (
            f"Revoked admin from {target_email}. Their next sign-in will "
            f"no longer have access to the admin panel."
        ),
        "email": target_email,
        "uid": user.uid,
    }
