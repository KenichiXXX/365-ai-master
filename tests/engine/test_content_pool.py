"""Contracts for the offline daily content bundle and replacement files."""

import json
from copy import deepcopy
from pathlib import Path

import pytest

from agentfit.engine.content_pool import load_content, validate

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = ROOT / "agentfit/engine/content_pool.json"
SKILL_IDS = (
    "rules_file", "web_search", "web_fetch", "plan_mode", "todo_list",
    "ask_first", "subagent", "light_model", "effort_up", "first_skill",
    "mcp", "hook", "compact", "worktree", "codex_agents", "init_cmd",
    "clear_session", "resume", "at_mention", "paste_image", "headless",
    "custom_command", "review_diff", "permissions",
)


def test_bundled_content_loads_and_validates():
    content = load_content(None)
    assert content == json.loads(BUNDLE.read_text(encoding="utf-8"))
    assert content["version"] == 1
    assert content["updated_at"] == "2026-10-21"
    assert validate(content)
    assert tuple(card["id"] for card in content["skills"]) == SKILL_IDS


def test_skill_copy_matches_plan_exactly():
    plan = (ROOT / "docs/superpowers/plans/2026-10-21-macos-newbie-village.md").read_text(encoding="utf-8")
    table = plan.split("**Skill cards**", 1)[1].split("**Rankings and tips:**", 1)[0]
    rows = [line for line in table.splitlines() if line.startswith("| ")][1:]
    cards = load_content(None)["skills"]
    assert len(cards) == len(rows) == 24
    for card, row in zip(cards, rows):
        # The effort alternatives use escaped Markdown table pipes.
        fields = row.replace(r"\|", "PIPE").strip("| ").split(" | ")
        card_id, detect, zh, en = [field.replace("PIPE", "|") for field in fields]
        assert card["id"] == card_id
        assert card["detect"] == detect
        for locale, copy in (("zh", zh), ("en", en)):
            assert [card[key][locale] for key in ("title", "prompt")] == [copy.split(" / ", 2)[i] for i in (0, 2)]


def test_public_copy_is_byte_identical():
    assert (ROOT / "content/daily.json").read_bytes() == BUNDLE.read_bytes()


def test_rankings_and_tips_keep_source_entries():
    from cloud.master import AGENT_POOL, CONTENT_POOL, SKILL_POOL

    content = load_content(None)
    for kind, source in (("skill", SKILL_POOL), ("agent", AGENT_POOL)):
        rankings = content["rankings"][kind]
        assert len(rankings) == len(source)
        for item, original in zip(rankings, source):
            assert item["name"] == original.name
            assert item["url"] == original.url
            assert item["tagline"]["zh"] == original.tagline
            assert item["match"] == []
    tips = content["tips"]
    originals = [item for item in CONTENT_POOL if item.kind == "tip"]
    assert len(tips) == len(originals)
    assert len({item["id"] for item in tips}) == len(tips)
    for item, original in zip(tips, originals):
        assert item["title"]["zh"] and item["title"]["en"]
        assert item["detail"]["zh"] and item["detail"]["en"]
        assert item["source"] == original.source


def test_valid_override_is_loaded(tmp_path):
    content = load_content(None)
    content["skills"][0]["title"]["en"] = "Replacement title"
    path = tmp_path / "daily.json"
    path.write_text(json.dumps(content), encoding="utf-8")
    assert load_content(path) == content


@pytest.mark.parametrize("raw", ["{", "null", "[]", "42", '{"version": 2}', '{"version": 1}'])
def test_unusable_json_falls_back(tmp_path, raw):
    path = tmp_path / "daily.json"
    path.write_text(raw, encoding="utf-8")
    assert load_content(path) == load_content(None)


def test_missing_or_unreadable_file_falls_back(tmp_path):
    assert load_content(tmp_path / "missing.json") == load_content(None)
    assert load_content(tmp_path) == load_content(None)
    path = tmp_path / "invalid-encoding.json"
    path.write_bytes(b"\xff")
    assert load_content(path) == load_content(None)


@pytest.mark.parametrize("detect", [
    "tool:WebSearch", "tool:AskUserQuestion", "mcp", "skill_any", "sidechain",
    "hook", "light_model", "effort:high|xhigh|max", "effort:low", "compaction",
    "instructions:claude", "instructions:codex", "self",
])
def test_detect_grammar_accepts_supported_forms(detect):
    content = load_content(None)
    content["skills"][0]["detect"] = detect
    assert validate(content)


@pytest.mark.parametrize("detect", [
    "unknown", "tool:", "tool:Web Search", "tool:WebSearch\n", "effort:",
    "effort:high|", "effort:|high", "effort:high||max", "instructions:other",
    "instructions:claude|codex", "self:extra", None, [],
])
def test_bad_detect_is_rejected_and_override_falls_back(tmp_path, detect):
    content = load_content(None)
    content["skills"][0]["detect"] = detect
    assert not validate(content)
    path = tmp_path / "daily.json"
    path.write_text(json.dumps(content), encoding="utf-8")
    assert load_content(path) == load_content(None)


@pytest.mark.parametrize("section,field", [
    ("skills", "title"), ("skills", "why"), ("skills", "prompt"),
    ("skill", "tagline"), ("agent", "tagline"),
    ("tips", "title"), ("tips", "detail"),
])
@pytest.mark.parametrize("locale", ["zh", "en"])
@pytest.mark.parametrize("bad_text", [None, "", "   ", 1])
def test_missing_or_empty_translation_is_rejected(tmp_path, section, field, locale, bad_text):
    content = load_content(None)
    items = content["rankings"][section] if section in ("skill", "agent") else content[section]
    if bad_text is None:
        del items[0][field][locale]
    else:
        items[0][field][locale] = bad_text
    assert not validate(content)
    path = tmp_path / "daily.json"
    path.write_text(json.dumps(content), encoding="utf-8")
    assert load_content(path) == load_content(None)


def test_duplicate_skill_ids_are_rejected():
    content = load_content(None)
    content["skills"].append(deepcopy(content["skills"][0]))
    assert not validate(content)


@pytest.mark.parametrize("field", ["id", "level", "detect", "title", "why", "prompt"])
def test_skill_requires_all_fields(field):
    content = load_content(None)
    del content["skills"][0][field]
    assert not validate(content)


@pytest.mark.parametrize("level", [0, -1, True, "1", None])
def test_skill_level_is_a_positive_integer(level):
    content = load_content(None)
    content["skills"][0]["level"] = level
    assert not validate(content)


@pytest.mark.parametrize("bad", [None, [], {}, {"version": 1}, {"version": True}])
def test_malformed_schema_returns_false(bad):
    assert not validate(bad)


@pytest.mark.parametrize("section", ["skills", "rankings", "tips"])
@pytest.mark.parametrize("bad", [None, "wrong", 1, [None], [{}]])
def test_malformed_section_returns_false(section, bad):
    content = load_content(None)
    content[section] = bad
    assert not validate(content)


def test_build_includes_content_bundle():
    script = (ROOT / "scripts/build_engine.sh").read_text(encoding="utf-8")
    assert "--add-data agentfit/engine/content_pool.json:agentfit/engine" in script


@pytest.mark.parametrize("field,value", [("rotate", "false"), ("source", 7), ("updated_at", None)])
def test_invalid_ranking_metadata(field, value):
    data = load_content(None)
    data["rankings"][field] = value
    assert not validate(data)


@pytest.mark.parametrize("field,value", [("stars", "500"), ("stars", True),
                                         ("stars7d", "10"), ("stars7d", False)])
def test_invalid_ranking_stars(field, value):
    data = load_content(None)
    data["rankings"]["skill"][0][field] = value
    assert not validate(data)


def test_optional_ranking_metadata():
    data = load_content(None)
    data["rankings"].update(rotate=False, source="GitHub", updated_at="2026-10-21")
    data["rankings"]["skill"][0].update(stars=1234, stars7d=None)
    data["rankings"]["agent"][0].update(stars=1234, stars7d=-2)
    assert validate(data)


def test_training_card_level_sets():
    expected = {
        1: {"rules_file", "web_search", "web_fetch", "ask_first", "at_mention",
            "paste_image", "clear_session", "init_cmd"},
        2: {"plan_mode", "todo_list", "light_model", "effort_up", "first_skill",
            "compact", "resume", "review_diff", "codex_agents", "permissions"},
        3: {"subagent", "mcp", "hook", "worktree", "headless", "custom_command"},
    }
    cards = load_content(None)["skills"]
    assert {level: {c["id"] for c in cards if c["level"] == level}
            for level in (1, 2, 3)} == expected


@pytest.mark.parametrize("field", ["compatibility", "steps", "validator", "expected_signal", "limitations", "review_id"])
def test_reviewed_practice_metadata_required(field):
    content = load_content(None)
    del content["skills"][0][field]
    assert not validate(content)


def test_no_blanket_promises_in_reviewed_copy():
    content = load_content(None)
    for card in content["skills"] + content["tips"]:
        raw = json.dumps(card, ensure_ascii=False)
        assert not any(promise in raw for promise in ("问题少一半", "只按 1 折", "只收约 1 折", "返工大幅减少"))


@pytest.mark.parametrize("review", [None, 1, [], {}])
def test_malformed_review_returns_false(review):
    content = load_content(None)
    content["review_exercises"] = [review]
    assert not validate(content)


def tool_update():
    return {"id": "synthetic-release", "tool": "codex",
            "source_url": "https://github.com/openai/codex/releases/tag/test",
            "fetched_at": "2026-10-21", "released_at": "2026-10-20",
            "compatibility": {"format": "codex-response-usage-v1", "adapter_versions": ["1"]},
            "summary": {"zh": "测试更新", "en": "Synthetic update"}, "practice_id": "review_diff"}


def test_optional_public_sections():
    from agentfit.engine.prices import EMPTY_TABLE
    data = load_content(None)
    data.pop("tool_updates", None)
    data.pop("prices", None)
    assert validate(data)
    data.update(tool_updates=[tool_update()], prices=deepcopy(EMPTY_TABLE))
    assert validate(data)


@pytest.mark.parametrize("key,value", [
    ("tool", "gemini_cli"), ("source_url", "https://github.com/evil/codex/releases/tag/test"),
    ("source_url", "https://github.com@evil.example/openai/codex"),
    ("source_url", "javascript:alert(1)"), ("released_at", "2026-99-99"),
    ("fetched_at", "yesterday"), ("practice_id", "invented-practice"),
    ("compatibility", {"format": "codex-response-usage-v1", "adapter_versions": ["???"]}),
    ("compatibility", {"format": "", "adapter_versions": []}), ("summary", {"en": "only"}),
])
def test_invalid_official_update_is_rejected(key, value, tmp_path):
    data = load_content(None)
    update = tool_update()
    update[key] = value
    data["tool_updates"] = [update]
    assert not validate(data)
    path = tmp_path / "public.json"
    path.write_text(json.dumps(data))
    assert load_content(path) == load_content(None)


@pytest.mark.parametrize("url", ["http://github.com/o/r", "file:///etc/passwd", "https://localhost/a",
    "https://127.0.0.1/a", "https://user:pass@github.com/o/r", "https://github.com/o/r?token=secret",
    "https://github.com/o/r#tracking", "https://private.local/a", "https://github.com/white space"])
def test_unsafe_ranking_urls_are_rejected(url):
    data = load_content(None)
    data["rankings"]["skill"][0]["url"] = url
    assert not validate(data)


def test_update_visibility_requires_known_matching_format_and_adapter(tmp_path):
    from agentfit.engine.codex_book import relevant_updates
    data = load_content(None)
    data["tool_updates"] = [tool_update()]
    coverage = {"codex": {"format": "codex-response-usage-v1", "adapter_version": "1", "status": "ok"}}
    assert relevant_updates(data, coverage, "en")[0]["summary"] == "Synthetic update"
    for change in ({"format": "unknown"}, {"adapter_version": "2"}, {"status": "not_detected"}):
        assert relevant_updates(data, {"codex": {**coverage["codex"], **change}}, "en") == []
    assert relevant_updates(data, {}, "zh") == []


def test_ranking_provenance_survives_normalization_and_name_is_only_hint():
    from datetime import date
    from agentfit.engine.codex_book import daily_rankings
    from agentfit.engine.inventory import Inventory
    data = load_content(None)
    row = data["rankings"]["skill"][0]
    row.update(match=["demo"], source_url=row["url"], source_date="2026-10-20",
               source_type="repository", task_category="coding", compatibility=None,
               caution={"zh": "核对权限", "en": "Check permissions"})
    inv = Inventory(["demo"], 0, 0, 0, 0, 0)
    result = daily_rankings(data, {"codex": inv}, "en", date(2026, 10, 21), n=20)
    found = next(x for x in result["skill"] if x["name"] == row["name"])
    assert found["installation_hint"] is True
    assert found.get("installed", False) is False
    assert found["compatibility"] is None
    assert found["source_url"] == row["url"] and found["source_date"] == "2026-10-20"
    assert found["source_type"] == "repository" and found["task_category"] == "coding"
    assert found["caution"] == "Check permissions"
    assert result["origin"] == "bundled"


@pytest.mark.parametrize("field,value", [("origin", []), ("origin", 7)])
def test_malformed_public_origin_rejected(field, value):
    data = load_content(None)
    data["rankings"][field] = value
    assert not validate(data)


@pytest.mark.parametrize("field,value", [("source_type", []), ("compatibility", []),
    ("source_date", []), ("stars", 10 ** 400)])
def test_malformed_public_metadata_rejected(field, value):
    data = load_content(None)
    data["rankings"]["skill"][0][field] = value
    assert not validate(data)
