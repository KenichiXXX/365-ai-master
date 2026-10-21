"""Offline JSON entry point for the menu-bar app."""
import argparse
import json
from pathlib import Path


def main() -> int:
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
        args = parser.parse_args()
        enabled = None if args.tools is None else {tool.strip() for tool in args.tools.split(",") if tool.strip()}
        result = build_snapshot(args.home, args.state_dir, args.locale, enabled=enabled)
        output = json.dumps(result, ensure_ascii=False)
    except Exception as exc:
        print(json.dumps({"schema": 1, "error": type(exc).__name__}))
        return 2
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
