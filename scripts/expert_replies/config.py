"""Shared configuration for the expert-reply toolkit.

All state lives under DATA_DIR as plain JSON files so re-running any step
picks up where the last one left off instead of recreating accounts or
re-fetching everything from scratch.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

BASE_URL = os.environ.get("MASTODON_BASE_URL", "").rstrip("/")

DATA_DIR = Path(os.environ.get("EXPERT_REPLIES_DATA_DIR", Path(__file__).parent / "data"))
DATA_DIR.mkdir(parents=True, exist_ok=True)

INTERESTS_FILE = Path(os.environ.get("INTERESTS_FILE", DATA_DIR / "interests.json"))

ACCOUNTS_FILE = DATA_DIR / "accounts.json"
QUEUE_FILE = DATA_DIR / "queue.json"
DUPLICATES_FILE = DATA_DIR / "duplicates_report.json"
REPLIED_LOG_FILE = DATA_DIR / "replied_log.json"
CANDIDATES_XLSX_FILE = DATA_DIR / "candidate_posts.xlsx"

INTERNAL_API_TOKEN = os.environ.get("INTERNAL_API_TOKEN", "")

# Fake accounts need an email with a real, DNS-resolvable domain --
# EmailMxValidator does a live MX lookup on signup and rejects anything
# that doesn't resolve (e.g. the RFC-reserved .invalid TLD). Using a
# gmail.com (or other real inbox you control) address with +alias tagging
# gives every account a distinct, valid address that still lands in one
# inbox, e.g. base "you@gmail.com" -> "you+hesham_naguib237@gmail.com".
EMAIL_ALIAS_BASE = os.environ.get("EMAIL_ALIAS_BASE", "")


def require_email_alias_base() -> str:
    if not EMAIL_ALIAS_BASE or "@" not in EMAIL_ALIAS_BASE:
        raise SystemExit(
            "EMAIL_ALIAS_BASE is not set to a real address. Export it, e.g.:\n"
            "  export EMAIL_ALIAS_BASE=you@gmail.com"
        )
    return EMAIL_ALIAS_BASE

ACCOUNTS_PER_INTEREST = int(os.environ.get("ACCOUNTS_PER_INTEREST", "2"))
PAGES_PER_TAG = int(os.environ.get("PAGES_PER_TAG", "2"))
PAGE_LIMIT = int(os.environ.get("PAGE_LIMIT", "20"))
DUPLICATE_THRESHOLD = float(os.environ.get("DUPLICATE_THRESHOLD", "0.85"))


def require_base_url() -> str:
    if not BASE_URL:
        raise SystemExit(
            "MASTODON_BASE_URL is not set. Export it, e.g.:\n"
            "  export MASTODON_BASE_URL=https://your-instance.example"
        )
    return BASE_URL


def require_internal_token() -> str:
    if not INTERNAL_API_TOKEN:
        raise SystemExit(
            "INTERNAL_API_TOKEN is not set. Export the same value the server has as "
            "ENV['INTERNAL_API_TOKEN'], e.g.:\n"
            "  export INTERNAL_API_TOKEN=...\n"
        )
    return INTERNAL_API_TOKEN
