"""Entry point.

    python -m scripts.expert_replies sync-interests  # pull the interest+tags catalog from the live API
    python -m scripts.expert_replies accounts         # create/top-up fake accounts per interest
    python -m scripts.expert_replies fetch             # walk tags, queue parent posts, flag near-dupes
    python -m scripts.expert_replies reply             # interactively write + post replies
    python -m scripts.expert_replies reply --from-xlsx path/to/filled_in.xlsx
    python -m scripts.expert_replies export             # (re)write queue.json as an .xlsx
"""

import argparse

from . import config


def main():
    parser = argparse.ArgumentParser(prog="expert_replies")
    sub = parser.add_subparsers(dest="command", required=True)

    p_sync = sub.add_parser("sync-interests", help="fetch the interest catalog + tags from the live API")
    p_sync.add_argument("--interests-file", default=None)

    p_accounts = sub.add_parser("accounts", help="create/top-up fake accounts per interest")
    p_accounts.add_argument("--interests-file", default=None)
    p_accounts.add_argument("--per-interest", type=int, default=None)

    p_fetch = sub.add_parser("fetch", help="fetch candidate parent posts, first N pages per tag")
    p_fetch.add_argument("--interests-file", default=None)
    p_fetch.add_argument("--pages", type=int, default=None)

    p_reply = sub.add_parser("reply", help="write and post replies, interactively or from a filled-in .xlsx")
    p_reply.add_argument("--from-xlsx", default=None, help="path to an exported .xlsx with a filled-in Reply column")
    sub.add_parser("export", help="(re)write queue.json as a human-friendly .xlsx")

    args = parser.parse_args()

    if args.command == "sync-interests":
        from .interests import sync_interests_from_api
        from pathlib import Path
        result, skipped = sync_interests_from_api(
            save_to=Path(args.interests_file) if args.interests_file else None,
        )
        print(f"Synced {len(result)} interests" + (f", {len(skipped)} failed" if skipped else ""))
    elif args.command == "accounts":
        from .accounts import ensure_accounts
        from pathlib import Path
        ensure_accounts(
            interests_file=Path(args.interests_file) if args.interests_file else None,
            per_interest=args.per_interest,
        )
    elif args.command == "fetch":
        from .fetch import fetch_candidates
        from pathlib import Path
        fetch_candidates(
            interests_file=Path(args.interests_file) if args.interests_file else None,
            pages=args.pages,
        )
    elif args.command == "reply":
        from pathlib import Path
        if args.from_xlsx:
            from .reply import run_from_xlsx
            run_from_xlsx(Path(args.from_xlsx))
        else:
            from .reply import run_interactive
            run_interactive()
    elif args.command == "export":
        from .export import write_xlsx
        from .fetch import load_queue
        path = write_xlsx(load_queue())
        if path:
            print(f"Spreadsheet: {path}")


if __name__ == "__main__":
    main()
