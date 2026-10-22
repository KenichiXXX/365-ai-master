"""Main copy budgets; prompts and expanded info retain necessary detail."""
import json
from pathlib import Path

import pytest
from agentfit.engine import content as C


def check_text(text, locale, role, path, errors):
    # Chinese budgets count Han characters; English budgets count all characters.
    length = sum("\u3400" <= c <= "\u9fff" for c in text) if locale == "zh" else len(text)
    budget = {"title": (14, 32), "line": (18, 40), "step": (12, 40), "reason": (10, 32)}[role][locale != "zh"]
    if length > budget:
        errors.append(f"{path}: {length}>{budget}: {text}")


def walk(value, locale, path, errors, role="line"):
    if isinstance(value, str):
        check_text(value, locale, role, path, errors)
    elif isinstance(value, list):
        if role == "step" and len(value) > 3:
            errors.append(f"{path}: more than 3 steps")
        for index, item in enumerate(value):
            walk(item, locale, f"{path}[{index}]", errors, role)
    elif isinstance(value, dict):
        for key, item in value.items():
            # These are only copied to the clipboard or displayed in expanded ⓘ.
            if key in {"prompt", "no_project_prompt", "limitation", "limitations", "expected_signal"}:
                continue
            walk(item, locale, f"{path}.{key}", errors,
                 "title" if key == "title" else "step" if key == "steps" else role)


@pytest.mark.parametrize("locale", ["zh", "en"])
def test_main_copy_budgets(locale):
    errors = []
    for name in ["_QUEST_TEXT", "_DIMENSION_TIPS", "_POOL_TIPS", "_LABELS", "FIRST_PRACTICE"]:
        walk(getattr(C, name)[locale], locale, name, errors)
    for name in ["_BADGE_TITLES", "QUEST_EVIDENCE", "PRACTICE_EVIDENCE", "_COVERAGE_LABELS"]:
        for key, pair in getattr(C, name).items():
            check_text(pair[locale != "zh"], locale, "title" if name == "_BADGE_TITLES" else "line", f"{name}.{key}", errors)
    for name in ["_RANK_TITLES", "GAME_LEVELS"]:
        walk(getattr(C, name)[locale], locale, name, errors, "title")
    details = C.checkup_detail_copy(locale)
    for key, item in details.items():
        if isinstance(item, tuple):
            check_text(item[0], locale, "reason", f"details.{key}", errors)
            walk(item[1], locale, f"details.{key}.steps", errors, "step")
        else:
            walk(item, locale, f"details.{key}", errors)
    walk(C.practice_calendar_labels(locale), locale, "calendar", errors)
    walk(C.local_validation_labels(locale), locale, "validation", errors)
    for index, pair in enumerate(C.GAME_TIPS):
        check_text(pair[locale != "zh"], locale, "line", f"game.tips.{index}", errors)
    for key, (_, copy) in C.GAME_WEEKLY.items():
        check_text(copy[locale], locale, "title", f"game.weekly.{key}", errors)
    for filename in ["agentfit/engine/content_pool.json", "content/daily.json"]:
        data = json.loads(Path(filename).read_text())
        for section in ["skills", "tips"]:
            for item in data[section]:
                for field, role in [("title", "title"), ("why", "line"), ("detail", "line"), ("steps", "step")]:
                    if field in item:
                        walk(item[field][locale], locale, f"{filename}.{item['id']}.{field}", errors, role)
    assert not errors, "\n".join(errors)


def test_harvester_trims_chinese_taglines_at_phrase_boundary():
    from scripts.harvest.harvest import translate_zh
    text = "让多个智能助手同时协作，自动完成复杂任务并检查结果"
    result = translate_zh(["Work together"], run_claude=lambda _: json.dumps([text]))
    assert result == ["让多个智能助手同时协作"]


@pytest.mark.parametrize("locale", ["zh", "en"])
def test_tip_keeps_expanded_caveats_localized(locale):
    from datetime import date
    from agentfit.engine.codex_book import daily_tip
    pool = json.loads(Path("agentfit/engine/content_pool.json").read_text())
    tip = daily_tip(pool, locale, date(2026, 10, 22))
    assert isinstance(tip["limitations"], str)
    assert tip["limitations"]


@pytest.mark.parametrize("bad", [None, "unlocalized", {"en": 3}])
def test_optional_tip_caveat_cannot_break_older_content(bad):
    from datetime import date
    from agentfit.engine.codex_book import daily_tip
    content = {"tips": [{"title": {"en": "Review the plan"},
                         "detail": {"en": "Read it before acting"}, "limitations": bad}]}
    assert "limitations" not in daily_tip(content, "en", date(2026, 10, 22))
