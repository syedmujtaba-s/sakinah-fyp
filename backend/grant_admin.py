"""
One-off script to grant or revoke the `admin: true` custom claim on a
Firebase Auth user — used to gate /api/admin/* and the admin panel.

Usage (from backend/ with .venv active):
    python grant_admin.py grant some.user@example.com
    python grant_admin.py revoke some.user@example.com
    python grant_admin.py whois some.user@example.com   # show current claims

Auth resolution mirrors backend/auth.py: FIREBASE_SERVICE_ACCOUNT_JSON env
var first, then GOOGLE_APPLICATION_CREDENTIALS, then
backend/serviceAccountKey.json.

After granting, the user must sign out and back in (or wait up to 1 hour)
before their ID token carries the new claim — that's a Firebase rule, not
ours.
"""
from __future__ import annotations

import json
import os
import sys


def _init_firebase() -> None:
    import firebase_admin
    from firebase_admin import credentials

    if firebase_admin._apps:
        return

    inline = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
    if inline:
        firebase_admin.initialize_app(credentials.Certificate(json.loads(inline)))
        return

    cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if not cred_path:
        local = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
        if os.path.isfile(local):
            cred_path = local

    if cred_path and os.path.isfile(cred_path):
        firebase_admin.initialize_app(credentials.Certificate(cred_path))
    else:
        firebase_admin.initialize_app()


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in {"grant", "revoke", "whois"}:
        print(__doc__)
        return 2

    action, email = sys.argv[1], sys.argv[2]
    _init_firebase()
    from firebase_admin import auth as fb_auth

    try:
        user = fb_auth.get_user_by_email(email)
    except fb_auth.UserNotFoundError:
        print(f"No Firebase user with email {email!r}")
        return 1

    print(f"Found user: uid={user.uid}  email={user.email}")
    print(f"Current custom claims: {user.custom_claims or {}}")

    if action == "whois":
        return 0

    claims = dict(user.custom_claims or {})
    if action == "grant":
        claims["admin"] = True
    else:
        claims.pop("admin", None)

    fb_auth.set_custom_user_claims(user.uid, claims)
    print(f"New custom claims: {claims}")
    print("Done. The user must sign out and back in for the new ID token "
          "to carry the updated claim.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
