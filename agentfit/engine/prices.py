"""Offline reviewed USD estimates. No tier fallback; no bundled invented prices."""
from datetime import date
from math import isfinite
import re

CATEGORIES = ("input", "output", "cache_read", "cache_write")
EMPTY_TABLE = {"version": "unreviewed-v1", "reviewed_at": None, "currency": "USD",
               "unit": "per_million_tokens", "models": []}


def validate_prices(table):
    if not isinstance(table, dict) or not isinstance(table.get("version"), str) or not table["version"]:
        return False
    if table.get("currency") != "USD" or table.get("unit") != "per_million_tokens":
        return False
    try:
        if table.get("reviewed_at") is not None:
            date.fromisoformat(table["reviewed_at"])
        rows = table["models"]
        if not isinstance(rows, list) or (rows and table.get("reviewed_at") is None):
            return False
        seen = set()
        for row in rows:
            if not isinstance(row, dict) or not re.fullmatch(r"[A-Za-z0-9_.:-]{1,160}", row.get("model", "")):
                return False
            date.fromisoformat(row["source_date"])
            if not re.fullmatch(r"https://[A-Za-z0-9.-]+/[^\s]*", row["source_url"]):
                return False
            # Logs only prove tool identity. Batch, region, long-context, TTL etc.
            # cannot be assumed; such price rows are unsupported, not guessed.
            conditions = row["conditions"]
            if not isinstance(conditions, dict) or set(conditions) != {"tool"}:
                return False
            if conditions["tool"] not in {"claude_code", "codex", "gemini_cli", "opencode", "qwen_code"}:
                return False
            key = (row["model"], conditions["tool"])
            if key in seen:
                return False
            seen.add(key)
            for category in CATEGORIES:
                value = row[category]
                if value is not None and (type(value) not in (int, float) or not isfinite(value) or value < 0):
                    return False
    except (KeyError, TypeError, ValueError):
        return False
    return True


def estimate(events, table=None):
    table = table if validate_prices(table) else EMPTY_TABLE
    rows = {(r["model"], r["conditions"]["tool"]): r for r in table["models"]}
    categories = dict.fromkeys(CATEGORIES, 0)
    matched = unknown = 0
    subtotal = 0.0
    unknown_models = set()
    for event in events:
        row = rows.get((event.model, event.tool), {})
        for category in CATEGORIES:
            tokens = max(getattr(event, category), 0)
            categories[category] += tokens
            if row.get(category) is None:
                unknown += tokens
                if tokens:
                    unknown_models.add(event.model)
            else:
                matched += tokens
                subtotal += tokens * row[category] / 1e6
    total = matched + unknown
    return {"price_version": table["version"], "reviewed_at": table["reviewed_at"],
            "currency": "USD", "unit": "per_million_tokens",
            "matched_subtotal_usd": round(subtotal, 8),
            "total_usd": round(subtotal, 8) if total and not unknown else None,
            "matched_tokens": matched, "unknown_tokens": unknown,
            "coverage_pct": matched / total * 100 if total else None,
            "unknown_models": sorted(unknown_models), "token_categories": categories}
