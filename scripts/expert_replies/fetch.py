"""Walks the supertags file supertag by supertag, pulling the first N pages
of each supertag's combined tags timeline (all its tags in one request via
POST /api/v1/timelines/tags), keeping only parent statuses (not replies)
that have no replies yet (not already answered), and flagging
near-duplicates for later manual cleanup.

Results are written to queue.json (candidates to reply to) and
duplicates_report.json (flagged for deletion review -- nothing is deleted
or skipped automatically).
"""

import json

from . import config
from .accounts import load_store, load_supertags, random_account
from .api_client import ApiError, MastodonClient
from .dedup import find_near_duplicates, strip_html
from .export import write_xlsx


def load_queue():
    if config.QUEUE_FILE.exists():
        return json.loads(config.QUEUE_FILE.read_text())
    return []


def save_queue(queue):
    config.QUEUE_FILE.write_text(json.dumps(queue, ensure_ascii=False, indent=2))


def load_duplicates():
    if config.DUPLICATES_FILE.exists():
        return json.loads(config.DUPLICATES_FILE.read_text())
    return []


def save_duplicates(duplicates):
    config.DUPLICATES_FILE.write_text(json.dumps(duplicates, ensure_ascii=False, indent=2))


def fetch_candidates(supertags_file=None, pages=None):
    pages = pages or config.PAGES_PER_TAG
    supertags = load_supertags(supertags_file)
    store = load_store()

    queue = load_queue()
    queue_by_id = {item["id"]: item for item in queue}

    collected = []  # statuses gathered this run, for cross-tag dedup

    for entry in supertags:
        supertag = entry["supertag"]
        try:
            account = random_account(store, supertag)
        except RuntimeError as e:
            print(f"[{supertag}] skipping fetch: {e}")
            continue

        client = MastodonClient(access_token=account["access_token"])

        tags = entry["tags"]
        wanted = {tag.lower() for tag in tags}
        max_id = None
        for page in range(1, pages + 1):
            try:
                statuses = client.tags_timeline(tags, token=account["access_token"], max_id=max_id)
            except ApiError as e:
                print(f"[{supertag}] page {page} failed: {e}")
                break

            if not statuses:
                break

            print(f"[{supertag}] page {page}: {len(statuses)} statuses")

            for status in statuses:
                if status.get("in_reply_to_id"):
                    continue  # only parent (non-reply) statuses
                if status.get("replies_count", 0) > 0:
                    continue  # already has a reply from someone -- treat as answered

                existing = queue_by_id.get(status["id"])
                if existing is not None:
                    # Same status matched another supertag's tags too -- note it
                    # there instead of dropping it, so filtering by supertag in
                    # the spreadsheet doesn't miss it.
                    matched_supertags = existing.setdefault("matched_supertags", [existing["supertag"]])
                    if supertag not in matched_supertags:
                        matched_supertags.append(supertag)
                    continue

                matched_tags = [t["name"] for t in status.get("tags", []) if t["name"].lower() in wanted]

                item = {
                    "id": status["id"],
                    "supertag": supertag,
                    "matched_supertags": [supertag],
                    "tag": ", ".join(matched_tags) if matched_tags else None,
                    "url": status.get("url"),
                    "account_acct": status.get("account", {}).get("acct"),
                    "content_text": strip_html(status.get("content", "")),
                    "created_at": status.get("created_at"),
                    "is_duplicate": False,
                    "duplicate_of": None,
                    "replied": False,
                }
                queue.append(item)
                collected.append(item)
                queue_by_id[item["id"]] = item

            max_id = statuses[-1]["id"]
            if len(statuses) < config.PAGE_LIMIT:
                break  # short page means no more results

    duplicates = load_duplicates()
    flagged = find_near_duplicates(collected)
    for flag in flagged:
        item = queue_by_id.get(flag["id"])
        if item is None:
            continue
        item["is_duplicate"] = True
        item["duplicate_of"] = flag["duplicate_of"]
        duplicates.append(flag)

    save_queue(queue)
    save_duplicates(duplicates)
    xlsx_path = write_xlsx(queue)

    print(f"\nCollected {len(collected)} new parent statuses, flagged {len(flagged)} as near-duplicates.")
    if xlsx_path:
        print(f"Spreadsheet: {xlsx_path}")
    return queue, duplicates
