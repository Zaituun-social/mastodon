"""Streamlit dashboard for the whole expert-reply toolkit -- a web UI
covering everything the CLI steps do (see cli.py / run.sh), so nothing
requires the terminal:

- Interests & Accounts: sync the interest+tags catalog from the live API,
  and create/top-up the fake account pool per interest.
- Fetch: pull the latest candidate posts for each interest.
- Reply: review pending posts one at a time and post replies (same
  underlying logic as reply.run_interactive(), just a web form instead of
  terminal prompts).
- Export & Log: (re)generate and download the review spreadsheet, and see
  what's already been replied to.

Run via:
    ./run.sh app
or directly:
    streamlit run scripts/expert_replies/app.py
"""

import io
import sys
from contextlib import redirect_stdout
from pathlib import Path

import pandas as pd
import streamlit as st

# Streamlit executes this file as a standalone script, not as part of the
# `scripts.expert_replies` package, so relative imports don't work here --
# put the repo root on sys.path and import absolutely instead.
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.expert_replies import config
from scripts.expert_replies.accounts import ensure_accounts, load_store
from scripts.expert_replies.api_client import ApiError
from scripts.expert_replies.export import write_xlsx
from scripts.expert_replies.fetch import fetch_candidates, load_duplicates, load_queue
from scripts.expert_replies.interests import sync_interests_from_api
from scripts.expert_replies.reply import load_replied_log, _post_reply

st.set_page_config(page_title="Expert Replies", page_icon="\U0001F4AC", layout="wide")


def _load():
    st.session_state.store = load_store()
    st.session_state.queue = load_queue()
    st.session_state.log = load_replied_log()
    st.session_state.duplicates = load_duplicates()
    st.session_state.idx = 0


if "queue" not in st.session_state:
    _load()


def _load_interests_file():
    if config.INTERESTS_FILE.exists():
        import json
        return json.loads(config.INTERESTS_FILE.read_text())
    return []


def _run_captured(fn, *args, **kwargs):
    """Runs fn with stdout captured, so its print() progress lines can be
    shown in the UI instead of only going to the terminal running Streamlit."""
    buf = io.StringIO()
    try:
        with redirect_stdout(buf):
            result = fn(*args, **kwargs)
        return result, buf.getvalue(), None
    except (ApiError, SystemExit, RuntimeError) as e:
        return None, buf.getvalue(), str(e)


st.title("\U0001F4AC Expert Replies")

if not config.BASE_URL:
    st.warning(
        "MASTODON_BASE_URL isn't set (check scripts/expert_replies/.env) -- "
        "most of this dashboard needs it to talk to the server."
    )

with st.sidebar:
    st.subheader("Status")
    if st.button("\U0001F504 Reload everything from disk", width="stretch"):
        _load()
        st.rerun()

    total = len(st.session_state.queue)
    replied = sum(1 for i in st.session_state.queue if i["replied"])
    duplicate_ct = sum(1 for i in st.session_state.queue if i["is_duplicate"])
    interest_ct = len({i["interest"] for i in st.session_state.queue}) if st.session_state.queue else 0
    account_ct = sum(len(v) for v in st.session_state.store.get("accounts", {}).values())

    st.metric("Replied", f"{replied} / {total}")
    st.metric("Interests with pending posts", interest_ct)
    st.metric("Flagged duplicates", duplicate_ct)
    st.metric("Accounts in pool", account_ct)

interests_data = _load_interests_file()

tab_reply, tab_interests, tab_fetch, tab_export = st.tabs(
    ["✅ Reply", "\U0001F331 Interests & Accounts", "\U0001F4E5 Fetch", "\U0001F4E4 Export & Log"]
)

# -- Reply -----------------------------------------------------------------

with tab_reply:
    with st.expander("Filters", expanded=False):
        # Union of the current interest catalog and whatever's actually in the
        # queue: a synced interest shows up here even before its first fetch,
        # and older posts filed under a since-retired interest name stay
        # reachable instead of silently disappearing from the filter.
        catalog_names = {e["interest"] for e in interests_data}
        queue_names = {item["interest"] for item in st.session_state.queue}
        interests = sorted(catalog_names | queue_names)
        interest_filter = st.selectbox("Interest", ["All"] + interests, key="reply_interest_filter")
        hide_duplicates = st.checkbox("Hide flagged duplicates", value=True, key="reply_hide_dupes")

    def _pending():
        items = [i for i in st.session_state.queue if not i["replied"]]
        if interest_filter != "All":
            items = [i for i in items if i["interest"] == interest_filter]
        if hide_duplicates:
            items = [i for i in items if not i["is_duplicate"]]
        return items

    pending = _pending()

    if not pending:
        st.success("Nothing left to reply to here. Use the Fetch tab to pull more posts, or adjust the filters.")
    else:
        if st.session_state.idx >= len(pending):
            st.session_state.idx = 0

        item = pending[st.session_state.idx]

        st.caption(f"{st.session_state.idx + 1} of {len(pending)} pending")

        if item["is_duplicate"]:
            st.warning(f"Flagged as a near-duplicate of status {item['duplicate_of']} -- consider skipping.")

        st.markdown(f"**interest:** `{item['interest']}` &nbsp;&nbsp; **tag:** #{item['tag']}")
        st.markdown(f"**from:** @{item['account_acct']} &nbsp;&nbsp; [{item['url']}]({item['url']})")
        st.divider()
        st.write(item["content_text"])
        st.divider()

        reply_text = st.text_area(
            "Reply", key=f"reply_{item['id']}", height=140, placeholder="Write the reply here..."
        )

        col_skip, col_post = st.columns(2)

        with col_skip:
            if st.button("⏭️ Skip", width="stretch"):
                st.session_state.idx += 1
                st.rerun()

        with col_post:
            if st.button(
                "✅ Post reply", type="primary", width="stretch", disabled=not reply_text.strip()
            ):
                try:
                    account, status = _post_reply(
                        st.session_state.store,
                        st.session_state.queue,
                        st.session_state.log,
                        item,
                        reply_text.strip(),
                    )
                except ApiError as e:
                    st.error(f"Failed to post: {e}")
                except SystemExit as e:
                    st.error(str(e))
                else:
                    st.toast(f"Replied as @{account['username']} -> {status.get('url')}")
                    st.rerun()

# -- Interests & Accounts ---------------------------------------------------

with tab_interests:
    st.subheader("Interest catalog")
    st.caption(
        f"Source file: `{config.INTERESTS_FILE}` -- each interest needs its tags synced here before "
        "accounts or fetch can use it."
    )

    if st.button("\U0001F310 Sync interests from server", help="Pulls the curated interest + tag list from the live API"):
        with st.spinner("Fetching interest catalog from the API..."):
            sync_result, log_output, error = _run_captured(sync_interests_from_api)
        if error:
            st.error(f"Sync failed: {error}")
        else:
            interests_data, skipped = sync_result
            st.success(f"Synced {len(interests_data)} interests" + (f", {len(skipped)} failed" if skipped else ""))
            if skipped:
                st.warning("Failed to fetch tags for: " + ", ".join(name for name, _ in skipped))

    if interests_data:
        st.dataframe(
            pd.DataFrame(
                [{"Interest": e["interest"], "Tags": len(e["tags"])} for e in interests_data]
            ),
            width="stretch",
            hide_index=True,
        )
    else:
        st.info("No interests file yet -- sync from the server or point INTERESTS_FILE at an existing one.")

    st.divider()
    st.subheader("Fake account pool")

    col_per, col_btn = st.columns([1, 2])
    with col_per:
        per_interest = st.number_input(
            "Accounts per interest", min_value=1, value=config.ACCOUNTS_PER_INTEREST, step=1
        )
    with col_btn:
        st.write("")
        st.write("")
        if st.button("\U0001F464 Create/top-up accounts", disabled=not interests_data):
            with st.spinner("Creating accounts..."):
                _, log_output, error = _run_captured(ensure_accounts, per_interest=int(per_interest))
            if error:
                st.error(f"Failed: {error}")
            else:
                st.session_state.store = load_store()
                st.success("Account pool updated.")
            if log_output.strip():
                with st.expander("Log"):
                    st.code(log_output)

    rows = [
        {"Interest": interest, "Username": acct["username"], "Display name": acct["display_name"]}
        for interest, accts in st.session_state.store.get("accounts", {}).items()
        for acct in accts
    ]
    if rows:
        st.dataframe(pd.DataFrame(rows), width="stretch", hide_index=True)
    else:
        st.info("No accounts created yet.")

# -- Fetch -------------------------------------------------------------------

with tab_fetch:
    st.subheader("Fetch latest candidate posts")
    st.caption("Pulls parent posts with no replies yet from each interest's tags, and flags near-duplicates.")

    pages = st.number_input("Pages per interest", min_value=1, value=config.PAGES_PER_TAG, step=1)

    if st.button("\U0001F4E5 Fetch latest posts", type="primary", disabled=not interests_data):
        with st.spinner("Fetching..."):
            (result, log_output, error) = _run_captured(fetch_candidates, pages=int(pages))
        if error:
            st.error(f"Fetch failed: {error}")
        else:
            queue, duplicates = result
            st.session_state.queue = queue
            st.session_state.duplicates = duplicates
            st.success("Fetch complete -- see log below for how many new posts were collected.")
        if log_output.strip():
            with st.expander("Log", expanded=True):
                st.code(log_output)

    if not interests_data:
        st.info("Sync or provide an interests file first (Interests & Accounts tab).")

    if st.session_state.duplicates:
        st.divider()
        st.subheader("Flagged near-duplicates")
        st.dataframe(pd.DataFrame(st.session_state.duplicates), width="stretch", hide_index=True)

# -- Export & Log --------------------------------------------------------------

with tab_export:
    st.subheader("Review spreadsheet")

    if st.button("\U0001F4C4 Regenerate spreadsheet"):
        path = write_xlsx(st.session_state.queue)
        if path:
            st.success(f"Wrote {path}")
        else:
            st.error("Could not write the spreadsheet (probably open in Excel/Numbers -- close it and retry).")

    if config.CANDIDATES_XLSX_FILE.exists():
        st.download_button(
            "⬇️ Download candidate_posts.xlsx",
            data=config.CANDIDATES_XLSX_FILE.read_bytes(),
            file_name=config.CANDIDATES_XLSX_FILE.name,
            mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )

    st.divider()
    st.subheader("Replied log")

    if st.session_state.log:
        st.dataframe(
            pd.DataFrame(st.session_state.log)[
                ["created_at", "interest", "tag", "account", "reply_text", "reply_id"]
            ],
            width="stretch",
            hide_index=True,
        )
    else:
        st.info("Nothing replied to yet.")
