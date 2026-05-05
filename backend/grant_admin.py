"""
One-off script to grant or revoke admin / super-admin custom claims on a
Firebase Auth user — used to gate /api/admin/* and the admin panel.

Usage (from backend/ with .venv active):
    python grant_admin.py grant some.user@example.com
    python grant_admin.py revoke some.user@example.com
    python grant_admin.py whois some.user@example.com   # show current claims
    python grant_admin.py list                          # list all admins

Super-admin (can grant/revoke admin from the UI panel):
    python grant_admin.py grant-super some.user@example.com   # sets admin AND superAdmin
    python grant_admin.py revoke-super some.user@example.com  # removes superAdmin only
    python grant_admin.py list-super                          # list all super-admins

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


def _scan_users(predicate):
    from firebase_admin import auth as fb_auth
    matches = []
    page = fb_auth.list_users()
    while page:
        for user in page.users:
            if predicate(user.custom_claims or {}):
                matches.append(user)
        page = page.get_next_page()
    return matches


def _list_admins() -> int:
    print("Scanning all Firebase users for admin claim...")
    admins = _scan_users(lambda c: c.get("admin"))
    if not admins:
        print("No admins found.")
        return 0
    print(f"\n{len(admins)} admin(s):")
    for u in admins:
        is_super = (u.custom_claims or {}).get("superAdmin")
        tag = "  [SUPER-ADMIN]" if is_super else ""
        print(f"  - {u.email or '(no email)'}    uid={u.uid}{tag}")
    return 0


def _list_super_admins() -> int:
    print("Scanning all Firebase users for superAdmin claim...")
    supers = _scan_users(lambda c: c.get("superAdmin"))
    if not supers:
        print("No super-admins found.")
        return 0
    print(f"\n{len(supers)} super-admin(s):")
    for u in supers:
        print(f"  - {u.email or '(no email)'}    uid={u.uid}")
    return 0


_SINGLE_ARG_ACTIONS = {"list", "list-super"}
_TWO_ARG_ACTIONS = {
    "grant", "revoke", "whois",
    "grant-super", "revoke-super",
}


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] in _SINGLE_ARG_ACTIONS:
        _init_firebase()
        if sys.argv[1] == "list":
            return _list_admins()
        if sys.argv[1] == "list-super":
            return _list_super_admins()

    if len(sys.argv) != 3 or sys.argv[1] not in _TWO_ARG_ACTIONS:
        print(__doc__)
        return 2

    action, email = sys.argv[1], sys.argv[2].strip().lower()
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
    elif action == "revoke":
        claims.pop("admin", None)
    elif action == "grant-super":
        # Super-admin is a strict superset of admin: every super-admin
        # must also have admin=True so the regular require_admin gate
        # on /api/admin/* still passes for them.
        claims["admin"] = True
        claims["superAdmin"] = True
    elif action == "revoke-super":
        # Only remove superAdmin; preserve regular admin claim if present.
        claims.pop("superAdmin", None)
    else:
        print(f"Unknown action: {action!r}")
        return 2

    fb_auth.set_custom_user_claims(user.uid, claims)
    print(f"New custom claims: {claims}")
    print("Done. The user must sign out and back in for the new ID token "
          "to carry the updated claim.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
