"""Offline JSON entry point for the menu-bar app."""
from datetime import datetime, timezone
import argparse
import json
import fcntl
from pathlib import Path


def main(argv: list[str] | None = None) -> int:
    try:
        from agentfit.engine.content import locale_from_env
        from agentfit.engine.snapshot import build_snapshot

        parser = argparse.ArgumentParser()
        commands = parser.add_subparsers(dest="command", required=True)
        snapshot = commands.add_parser("snapshot")
        snapshot.add_argument("--json", action="store_true")
        snapshot.add_argument("--home", type=Path, default=Path.home())
        snapshot.add_argument("--state-dir", type=Path,
                              default=Path.home() / "Library/Application Support/365AIMaster")
        snapshot.add_argument("--locale", choices=("zh", "en"), default=locale_from_env())
        snapshot.add_argument("--tools")
        snapshot.add_argument("--content", type=Path)
        tried = commands.add_parser("mark-tried")
        tried.add_argument("card_id")
        tried.add_argument("--state-dir", type=Path,
                           default=Path.home() / "Library/Application Support/365AIMaster")
        from agentfit.engine.action_rules import FEEDBACK, REASONS, action_feedback, reset_preferences
        feedback = commands.add_parser("action-feedback")
        feedback.add_argument("action_id")
        feedback.add_argument("feedback", choices=FEEDBACK)
        feedback.add_argument("--reason", choices=REASONS)
        reset = commands.add_parser("reset-action-preferences")
        for command in (feedback, reset):
            command.add_argument("--state-dir", type=Path,
                                 default=Path.home() / "Library/Application Support/365AIMaster")
        args = parser.parse_args(argv)
        args.state_dir.mkdir(parents=True, exist_ok=True)
        # Every CLI mutation, including snapshots, uses the same local command lock.
        lock = (args.state_dir / "engine.lock").open("a")
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.command == "action-feedback":
            result = {"ok": action_feedback(args.state_dir / "progress.json", args.action_id,
                        args.feedback, args.reason, datetime.now(timezone.utc).astimezone().date())}
        elif args.command == "reset-action-preferences":
            reset_preferences(args.state_dir / "progress.json")
            result = {"ok": True}
        elif args.command == "mark-tried":
            from agentfit.engine.codex_book import mark_tried
            result = {"ok": mark_tried(args.card_id, args.state_dir / "progress.json",
                                       datetime.now(timezone.utc))}
        else:
            enabled = None if args.tools is None else {tool.strip() for tool in args.tools.split(",") if tool.strip()}
            result = build_snapshot(args.home, args.state_dir, args.locale,
                                    enabled=enabled, content=args.content)
        output = json.dumps(result, ensure_ascii=False)
    except Exception as exc:
        print(json.dumps({"schema": 3, "error": type(exc).__name__}))
        return 2
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
