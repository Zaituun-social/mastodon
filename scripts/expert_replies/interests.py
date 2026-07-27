"""Syncs the interest catalog (name + associated tags) from this instance's
live API, so the interests file that accounts.py/fetch.py consume doesn't
have to be hand-maintained.

Public endpoints only, both token-optional (preferring an existing
account's token if one is on hand, so this still works if the instance
disallows fully anonymous API access): GET /api/v1/interests for the
interest list, and the paginated GET /api/v1/interests/:name/tags for each
interest's tags.
"""

import json

from . import config
from .accounts import load_store
from .api_client import ApiError, MastodonClient


def _any_token(store):
    for accounts in store.get("accounts", {}).values():
        for account in accounts:
            if account.get("access_token"):
                return account["access_token"]
    return None


def sync_interests_from_api(save_to=None):
    """Fetches the full interest catalog + tags from the server and writes
    it to save_to (default config.INTERESTS_FILE) in the
    [{"interest": ..., "tags": [...]}, ...] shape accounts.py/fetch.py
    expect. Interests with no tags assigned yet are skipped -- there's
    nothing to fetch posts for.

    An interest whose tags fail to fetch this run keeps its last-synced
    entry from save_to instead of being dropped, so a partial or total
    failure never wipes out previously-synced data. Returns
    (list written, [(name, error), ...])."""

    save_to = save_to or config.INTERESTS_FILE
    store = load_store()
    token = _any_token(store)

    existing = {}
    if save_to.exists():
        existing = {entry["interest"]: entry for entry in json.loads(save_to.read_text())}

    client = MastodonClient()
    interests = client.list_interests(token=token)

    result = []
    skipped = []
    for interest in interests:
        name = interest["name"]
        if not interest.get("tags_count"):
            continue
        try:
            tags = client.list_interest_tags(name, token=token)
        except ApiError as e:
            skipped.append((name, str(e)))
            if name in existing:
                result.append(existing[name])
            continue
        if not tags:
            continue
        result.append({"interest": name, "tags": tags})

    save_to.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    return result, skipped
