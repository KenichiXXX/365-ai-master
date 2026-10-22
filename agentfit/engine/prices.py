"""Offline API-equivalent estimates: exact reviewed rows, then known-tier approximations."""
from datetime import date
from math import isfinite
import re

from agentfit.pricing import TIER_PRICES, classify_model

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


def _tier_prices(event):
    # classify_model defaults arbitrary names to balanced for scoring. Do not
    # mistake that default for pricing evidence: allow only named known families.
    name = event.model.lower()
    claude = event.tool == "claude_code" and re.search(
        r"(?:^|[-_.])(opus|sonnet|haiku)(?:$|[-_.])", name)
    codex = event.tool == "codex" and re.fullmatch(
        r"gpt-6(?:\.\d+)?-(?:sol|astra|terra|luna)(?:[-.][a-z0-9]+)*", name)
    if not (claude or codex):
        return None
    input_price, output_price, cache_price = TIER_PRICES[classify_model(name)]
    # Cache writes use the input tier as an approximation, not an exact TTL rate.
    return dict(input=input_price, output=output_price,
                cache_read=cache_price, cache_write=input_price)


def estimate(events, table=None):
    table = table if validate_prices(table) else EMPTY_TABLE
    rows = {(r["model"], r["conditions"]["tool"]): r for r in table["models"]}
    categories = dict.fromkeys(CATEGORIES, 0)
    matched = unknown = 0
    subtotal = 0.0
    tier_tokens = 0
    unknown_models = set()
    for event in events:
        row = rows.get((event.model, event.tool))
        tier = _tier_prices(event) if row is None else None
        row = row if row is not None else tier or {}
        for category in CATEGORIES:
            tokens = max(getattr(event, category), 0)
            categories[category] += tokens
            if row.get(category) is None:
                unknown += tokens
                if tokens:
                    unknown_models.add(event.model)
            else:
                matched += tokens
                if tier is not None:
                    tier_tokens += tokens
                subtotal += tokens * row[category] / 1e6
    total = matched + unknown
    return {"price_version": table["version"] + ("+tier-v1" if tier_tokens else ""),
            "tier_estimated_tokens": tier_tokens, "reviewed_at": table["reviewed_at"],
            "currency": "USD", "unit": "per_million_tokens",
            "matched_subtotal_usd": round(subtotal, 8),
            "total_usd": round(subtotal, 8) if total and not unknown else None,
            "matched_tokens": matched, "unknown_tokens": unknown,
            "coverage_pct": matched / total * 100 if total else None,
            "unknown_models": sorted(unknown_models), "token_categories": categories}
