"""Validate and load the offline bilingual daily content pool."""

import json
import re
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


def validate(d: object) -> bool:
    """Return False for malformed schema v1 content, including incomplete copy."""
    if not isinstance(d, dict) or type(d.get("version")) is not int or d["version"] != 1:
        return False
    if not _text(d.get("updated_at")):
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
            if not isinstance(spec, dict) or not _text(spec.get("format")):
                return False
            versions = spec.get("adapter_versions")
            if not isinstance(versions, list) or not versions or not all(_text(v) for v in versions):
                return False

    if "rotate" in rankings and type(rankings["rotate"]) is not bool:
        return False
    if any(key in rankings and not _text(rankings[key]) for key in ("source", "updated_at")):
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
            for key in ("stars", "stars7d"):
                if key in item and not (key == "stars7d" and item[key] is None):
                    if type(item[key]) not in (int, float):
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
