"""Validate and load the offline bilingual daily content pool."""

import json
import re
from datetime import date
from pathlib import Path

_DETECT = re.compile(
    r"(?:tool:[A-Za-z][A-Za-z0-9_]*"
    r"|mcp|skill_any|sidechain|hook|light_model|compaction|self"
    r"|effort:[a-z][a-z0-9_]*(?:\|[a-z][a-z0-9_]*)*"
    r"|instructions:(?:claude|codex))"
)


def _text(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _bilingual(value: object) -> bool:
    return isinstance(value, dict) and all(_text(value.get(locale)) for locale in ("zh", "en"))


def public_url(value: object) -> bool:
    if not isinstance(value, str):
        return False
    match = re.fullmatch(r"https://([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)/[^\s?#\\]*", value)
    if not match:
        return False
    host = match[1].lower()
    return (not host.rsplit(".", 1)[1].isdigit()
            and not host.endswith((".local", ".localhost", ".internal", ".test", ".invalid")))


def _date(value: object) -> bool:
    try:
        return isinstance(value, str) and date.fromisoformat(value).isoformat() == value
    except ValueError:
        return False


def _compatibility(spec: object) -> bool:
    return (isinstance(spec, dict) and isinstance(spec.get("format"), str)
            and re.fullmatch(r"[a-z][a-z0-9-]{0,79}", spec["format"]) is not None
            and isinstance(spec.get("adapter_versions"), list) and bool(spec["adapter_versions"])
            and all(isinstance(v, str) and re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", v)
                    for v in spec["adapter_versions"]))


OFFICIAL_REPOS = {"claude_code": "anthropics/claude-code", "codex": "openai/codex"}


def validate_updates(updates: object, practice_ids: set[str]) -> bool:
    if not isinstance(updates, list) or len(updates) > 20:
        return False
    seen = set()
    for item in updates:
        if not isinstance(item, dict) or not _text(item.get("id")) or item["id"] in seen:
            return False
        seen.add(item["id"])
        repo = OFFICIAL_REPOS.get(item.get("tool")) if isinstance(item.get("tool"), str) else None
        url = item.get("source_url")
        if (not repo or not public_url(url) or not url.startswith(f"https://github.com/{repo}/releases/tag/")
                or not url.removeprefix(f"https://github.com/{repo}/releases/tag/")):
            return False
        if not _date(item.get("released_at")) or not _date(item.get("fetched_at")):
            return False
        if item["released_at"] > item["fetched_at"]:
            return False
        if not _compatibility(item.get("compatibility")) or not _bilingual(item.get("summary")):
            return False
        if not isinstance(item.get("practice_id"), str) or item["practice_id"] not in practice_ids:
            return False
    return True


def validate(d: object) -> bool:
    """Return False for malformed schema v1 content, including incomplete copy."""
    if not isinstance(d, dict) or type(d.get("version")) is not int or d["version"] != 1:
        return False
    if not _date(d.get("updated_at")):
        return False
    from agentfit.engine.prices import validate_prices
    if "prices" in d and not validate_prices(d["prices"]):
        return False
    if "prices" in d and any(not public_url(r.get("source_url")) for r in d["prices"]["models"]):
        return False
    skills, rankings, tips = d.get("skills"), d.get("rankings"), d.get("tips")
    if not isinstance(skills, list) or not isinstance(rankings, dict) or not isinstance(tips, list):
        return False

    ids = set()
    for card in skills:
        if not isinstance(card, dict) or not _text(card.get("id")):
            return False
        if card["id"] in ids:
            return False
        ids.add(card["id"])
        if type(card.get("level")) is not int or card["level"] < 1:
            return False
        detect = card.get("detect")
        if not isinstance(detect, str) or _DETECT.fullmatch(detect) is None:
            return False
        if not all(_bilingual(card.get(key)) for key in ("title", "why", "prompt")):
            return False

    reviews = d.get("review_exercises")
    if not isinstance(reviews, list):
        return False
    for card in reviews:
        if not isinstance(card, dict) or not _text(card.get("id")) or card["id"] in ids:
            return False
        if type(card.get("level")) is not int or card["level"] < 1:
            return False
        if not isinstance(card.get("detect"), str) or _DETECT.fullmatch(card["detect"]) is None:
            return False
        if not all(_bilingual(card.get(key)) for key in ("title", "why", "prompt")):
            return False
        ids.add(card["id"])
    for card in skills + reviews:
        if card.get("validator") != "self" and (not isinstance(card.get("validator"), str)
                or _DETECT.fullmatch(card["validator"]) is None):
            return False
        if not all(_bilingual(card.get(key)) for key in ("expected_signal", "limitations")):
            return False
        steps = card.get("steps")
        if not isinstance(steps, dict) or not all(isinstance(steps.get(loc), list)
                and steps[loc] and all(_text(step) for step in steps[loc]) for loc in ("zh", "en")):
            return False
        if not _text(card.get("review_id")):
            return False
        compatibility = card.get("compatibility")
        if not isinstance(compatibility, dict) or not compatibility:
            return False
        for tool, spec in compatibility.items():
            if tool not in {"claude_code", "codex", "gemini_cli", "qwen_code", "opencode"}:
                return False
            if not _compatibility(spec):
                return False

    if "tool_updates" in d and not validate_updates(d["tool_updates"], ids):
        return False

    if "rotate" in rankings and type(rankings["rotate"]) is not bool:
        return False
    if any(key in rankings and not _text(rankings[key]) for key in ("source", "updated_at")):
        return False
    if "updated_at" in rankings and not _date(rankings["updated_at"]):
        return False
    if rankings.get("origin", "bundled") not in ("bundled", "public"):
        return False

    for kind in ("skill", "agent"):
        items = rankings.get(kind)
        if not isinstance(items, list):
            return False
        for item in items:
            if not isinstance(item, dict) or not all(_text(item.get(key)) for key in ("name", "url")):
                return False
            if not _bilingual(item.get("tagline")):
                return False
            if not public_url(item["url"]):
                return False
            if item.get("source_url") is not None and not public_url(item["source_url"]):
                return False
            if item.get("source_date") is not None and not _date(item["source_date"]):
                return False
            if item.get("source_type", "curated") not in ("curated", "repository", "catalog"):
                return False
            if item.get("task_category") is not None and not _text(item["task_category"]):
                return False
            if "caution" in item and not _bilingual(item["caution"]):
                return False
            specs = item.get("compatibility")
            if specs is not None and (not isinstance(specs, dict) or not specs
                    or any(t not in {"claude_code", "codex", "gemini_cli", "opencode", "qwen_code"}
                           or not _compatibility(s) for t, s in specs.items())):
                return False
            for key in ("stars", "stars7d"):
                if key in item and not (key == "stars7d" and item[key] is None):
                    if type(item[key]) is not int or not -(2**53) < item[key] < 2**53:
                        return False
            match = item.get("match")
            if not isinstance(match, list) or not all(_text(name) for name in match):
                return False

    for tip in tips:
        if not isinstance(tip, dict) or not all(_text(tip.get(key)) for key in ("id", "source")):
            return False
        if not all(_bilingual(tip.get(key)) for key in ("title", "detail")):
            return False
    return True


def load_content(path: Path | None) -> dict:
    """Use a valid local replacement, otherwise read the bundled default."""
    if path is not None:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if validate(data):
                return data
        except (OSError, UnicodeError, ValueError):
            pass
    bundled = Path(__file__).with_name("content_pool.json")
    return json.loads(bundled.read_text(encoding="utf-8"))
