"""Creates and persists the pool of fake per-supertag accounts.

Uses this fork's internal API (/api/v1/internal/accounts + /internal/tokens,
guarded by X-Internal-Token) so accounts come out pre-confirmed and
pre-approved with a usable access token immediately -- no email
confirmation loop or OAuth app registration needed.

Everything is idempotent against accounts.json: accounts already recorded
there (with a token) are reused as-is, so re-running only tops up whatever
is missing -- e.g. after adding a new supertag, or resuming after a run
that got interrupted partway through.
"""

import json
import random

from . import config
from .api_client import ApiError, MastodonClient
from .names import FIRST_NAMES, LAST_NAMES


def load_store():
    if config.ACCOUNTS_FILE.exists():
        return json.loads(config.ACCOUNTS_FILE.read_text())
    return {"accounts": {}}


def save_store(store):
    config.ACCOUNTS_FILE.write_text(json.dumps(store, ensure_ascii=False, indent=2))


def load_supertags(path=None):
    return json.loads((path or config.SUPERTAGS_FILE).read_text())


def _aliased_email(username):
    local, domain = config.require_email_alias_base().split("@", 1)
    return f"{local}+{username}@{domain}"


def _pick_name(used_usernames):
    for _ in range(200):
        first_ar, first_en = random.choice(FIRST_NAMES)
        last_ar, last_en = random.choice(LAST_NAMES)
        suffix = str(random.randint(10, 9999))
        username = f"{first_en}_{last_en}{suffix}"
        if username not in used_usernames:
            return f"{first_ar} {last_ar}", username
    raise RuntimeError("could not find a free username after 200 attempts")


def ensure_accounts(supertags_file=None, per_supertag=None):
    """Make sure every supertag has `per_supertag` registered accounts,
    creating only whatever is missing. Returns the updated store."""

    per_supertag = per_supertag or config.ACCOUNTS_PER_SUPERTAG
    supertags = load_supertags(supertags_file)

    client = MastodonClient()
    store = load_store()

    used_usernames = {
        acct["username"]
        for accts in store["accounts"].values()
        for acct in accts
    }

    for entry in supertags:
        supertag = entry["supertag"]
        existing = store["accounts"].setdefault(supertag, [])
        missing = per_supertag - len(existing)
        if missing <= 0:
            continue

        print(f"[{supertag}] have {len(existing)}, creating {missing} more")
        for _ in range(missing):
            display_name, username = _pick_name(used_usernames)
            used_usernames.add(username)
            email = _aliased_email(username)

            try:
                created = client.internal_create_account(username, email)
                account_id = created["id"]
                token = client.internal_create_token(account_id)
                client.update_credentials(token["access_token"], display_name)
            except ApiError as e:
                print(f"  failed to create {username}: {e}")
                continue

            existing.append({
                "supertag": supertag,
                "account_id": account_id,
                "display_name": display_name,
                "username": username,
                "email": email,
                "password": created.get("password"),
                "access_token": token["access_token"],
            })
            save_store(store)
            print(f"  created @{username} ({display_name})")

    return store


def accounts_for_supertag(store, supertag):
    return store["accounts"].get(supertag, [])


def random_account(store, supertag):
    pool = accounts_for_supertag(store, supertag)
    if not pool:
        raise RuntimeError(f"no accounts registered for supertag {supertag!r}; run the `accounts` step first")
    return random.choice(pool)
