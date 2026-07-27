"""Two ways to write + post replies, neither of which generates reply text
automatically -- a person always writes it:

- run_interactive(): terminal prompt, one candidate at a time.
- run_from_xlsx(path): read a copy of candidate_posts.xlsx that's had its
  "Reply" column filled in (e.g. in Excel/Numbers/Sheets) and post each
  non-blank row. Rows are matched by Status ID, not position, so
  reordering/filtering/hiding rows in the spreadsheet is safe.

Near-duplicate flags from the fetch step are shown as a warning but don't
block replying either way; they're for the separate cleanup pass on
duplicates_report.json.
"""

import json

from openpyxl import load_workbook

from . import config
from .accounts import load_store, random_account
from .api_client import ApiError, MastodonClient
from .export import REPLY_COLUMN_HEADER, STATUS_ID_COLUMN_HEADER, write_xlsx
from .fetch import load_queue, save_queue


def load_replied_log():
    if config.REPLIED_LOG_FILE.exists():
        return json.loads(config.REPLIED_LOG_FILE.read_text())
    return []


def save_replied_log(log):
    config.REPLIED_LOG_FILE.write_text(json.dumps(log, ensure_ascii=False, indent=2))


def _post_reply(store, queue, log, item, reply_text):
    """Posts reply_text to item via a random account for its interest,
    marks item as replied, and persists queue.json + replied_log.json.
    Returns the created status dict, or raises ApiError."""

    account = random_account(store, item["interest"])
    client = MastodonClient(access_token=account["access_token"])

    status = client.post_status(account["access_token"], reply_text, in_reply_to_id=item["id"])

    item["replied"] = True
    save_queue(queue)

    log.append({
        "parent_id": item["id"],
        "reply_id": status.get("id"),
        "account": account["username"],
        "interest": item["interest"],
        "tag": item["tag"],
        "reply_text": reply_text,
        "created_at": status.get("created_at"),
    })
    save_replied_log(log)

    return account, status


def run_interactive():
    store = load_store()
    queue = load_queue()
    log = load_replied_log()

    pending = [item for item in queue if not item["replied"]]
    if not pending:
        print("Nothing left to reply to. Run the fetch step to pull more posts.")
        return

    print(f"{len(pending)} candidate post(s) to review.\n")

    for item in pending:
        print("-" * 60)
        print(f"interest: {item['interest']}   tag: #{item['tag']}")
        print(f"from: @{item['account_acct']}   url: {item['url']}")
        if item["is_duplicate"]:
            print(f"[!] flagged as near-duplicate of {item['duplicate_of']} -- consider skipping")
        print()
        print(item["content_text"])
        print()

        reply_text = input("Reply (blank = skip, 'q' = quit): ").strip()
        if reply_text.lower() == "q":
            break
        if not reply_text:
            continue

        try:
            account, status = _post_reply(store, queue, log, item, reply_text)
        except ApiError as e:
            print(f"  failed to post reply: {e}")
            continue

        write_xlsx(queue)
        print(f"  replied as @{account['username']} -> {status.get('url')}")

    print(f"\nDone for this session. Spreadsheet: {config.CANDIDATES_XLSX_FILE}")


def run_from_xlsx(path):
    store = load_store()
    queue = load_queue()
    log = load_replied_log()
    by_id = {item["id"]: item for item in queue}

    wb = load_workbook(path)
    ws = wb.active

    header = [cell.value for cell in next(ws.iter_rows(min_row=1, max_row=1))]
    if REPLY_COLUMN_HEADER not in header or STATUS_ID_COLUMN_HEADER not in header:
        raise SystemExit(
            f"{path} is missing a '{REPLY_COLUMN_HEADER}' or '{STATUS_ID_COLUMN_HEADER}' "
            "column -- export a fresh copy first (`... export`) and fill that one in."
        )
    reply_col = header.index(REPLY_COLUMN_HEADER)
    id_col = header.index(STATUS_ID_COLUMN_HEADER)

    posted = skipped = errors = 0

    for row in ws.iter_rows(min_row=2, values_only=True):
        status_id = row[id_col]
        reply_text = row[reply_col]

        if not status_id or not reply_text or not str(reply_text).strip():
            continue

        status_id = str(status_id)
        reply_text = str(reply_text).strip()
        item = by_id.get(status_id)

        if item is None:
            print(f"  status {status_id}: not in current queue (stale spreadsheet?), skipping")
            skipped += 1
            continue
        if item["replied"]:
            skipped += 1
            continue

        try:
            account, status = _post_reply(store, queue, log, item, reply_text)
        except ApiError as e:
            print(f"  status {status_id}: failed to post reply: {e}")
            errors += 1
            continue

        print(f"  status {status_id}: replied as @{account['username']} -> {status.get('url')}")
        posted += 1

    write_xlsx(queue)
    print(f"\nPosted {posted}, skipped {skipped} (already replied/blank/not found), errors {errors}.")
    print(f"Spreadsheet refreshed: {config.CANDIDATES_XLSX_FILE}")
