"""Offline contract for jev: only public names/descriptions enter the batch."""
import copy
import json
import subprocess
from datetime import date

import pytest

from scripts.harvest import harvest as h
from agentfit.engine.codex_book import daily_rankings
from agentfit.engine.content_pool import load_content, validate


def rows():
    return [h.to_ranking_item(f"o/{i}", f"https://github.com/o/{i}", f"Public tool {i}", None, 500, None)
            | {"private_extra": "never-send"} for i in range(3)]


def answer(spam=0.1, category="coding", beginner="4"):
    return {"answers": {"spam": {"type": "noul", "noul": spam},
                        "category": {"type": "choice", "choice": category},
                        "beginner": {"type": "score", "score": 3.1, "label": beginner}}}


def test_batch_public_fields_threshold_and_no_mutation():
    source = rows()
    before = copy.deepcopy(source)
    calls = []
    def run(argv, **kw):
        calls.append((argv, kw))
        if argv[1:] == ["auth", "status"]:
            return subprocess.CompletedProcess(argv, 0, "configured", "")
        states = [json.loads(line) for line in kw["input"].splitlines()]
        assert states == [{"name": f"o/{i}", "description": f"Public tool {i}"} for i in range(3)]
        output = [answer(0.799), answer(0.8), answer(0.99)]
        return subprocess.CompletedProcess(argv, 0, "\n".join(map(json.dumps, output)), "")
    result = h.judge_rankings(source, run_jev=run, find_jev=lambda _: "/fake/jev")
    assert len(result) == 1 and result[0]["name"] == "o/0"
    assert result[0]["category"] == "coding" and result[0]["beginner"] == 4
    assert source == before
    assert len(calls) == 2
    assert calls[1][0][1:] == ["run", str(h.JEV_SPEC), "-l", "--json"]
    assert all(kw["timeout"] <= 60 for _, kw in calls)
    spec = json.loads(h.JEV_SPEC.read_text())
    assert spec["questions"]["spam"]["criteria"] == {
        "true": "推广、卖课、引流、无实质功能", "false": "真实的开源工具或技能"}
    assert set(spec["questions"]["category"]["criteria"]) == h.RANKING_CATEGORIES
    assert spec["questions"]["beginner"]["criteria"] == ["1", "2", "3", "4", "5"]


@pytest.mark.parametrize("failure", ["missing", "key", "timeout", "partial", "malformed", "category", "beginner", "nan", "exit"])
def test_unavailable_or_invalid_results_preserve_rankings(failure, capsys):
    source = rows()
    def run(argv, **kw):
        if failure == "timeout":
            raise subprocess.TimeoutExpired(argv, 60)
        if argv[1:] == ["auth", "status"]:
            return subprocess.CompletedProcess(argv, int(failure == "key"), "", "")
        if failure == "exit":
            raise subprocess.CalledProcessError(2, argv, stderr="never-send")
        data = [answer() for _ in source]
        if failure == "partial": data.pop()
        if failure == "category": data[1]["answers"]["category"]["choice"] = "bad"
        if failure == "beginner": data[1]["answers"]["beginner"]["label"] = "6"
        if failure == "nan": data[1]["answers"]["spam"]["noul"] = float("nan")
        raw = "bad" if failure == "malformed" else "\n".join(map(json.dumps, data))
        return subprocess.CompletedProcess(argv, 0, raw, "")
    assert h.judge_rankings(source, run_jev=run, find_jev=lambda _: None if failure == "missing" else "/fake/jev") == source
    output = capsys.readouterr()
    assert len(output.err.splitlines()) == 1 and "never-send" not in output.err


def test_fields_survive_validation_and_local_snapshot():
    content = load_content(None)
    content["rankings"]["skill"][0].update(category="memory", beginner=4)
    assert validate(content)
    row = daily_rankings(content, {}, "en", date(2026, 10, 22), n=20)["skill"]
    row = next(r for r in row if r["name"] == content["rankings"]["skill"][0]["name"])
    assert row["category"] == "memory" and row["beginner"] == 4
    for key, value in [("category", "bad"), ("beginner", True), ("beginner", 6), ("beginner", 3.5)]:
        invalid = copy.deepcopy(content)
        invalid["rankings"]["skill"][0][key] = value
        assert not validate(invalid)


def test_main_applies_one_batch_to_all_rankings(tmp_path, monkeypatch):
    from tests.harvest.test_harvest import setup_main
    out, _, args = setup_main(tmp_path, monkeypatch)
    calls = []
    def judge(items):
        calls.append(items)
        return [{**item, "category": "coding", "beginner": 4} for item in items if item["name"] != "owner/skill-0"]
    monkeypatch.setattr(h, "judge_rankings", judge)
    assert h.main(args) == 0
    assert len(calls) == 1 and len(calls[0]) == 35
    content = json.loads(out.read_text())
    assert all(r["category"] == "coding" and r["beginner"] == 4
               for kind in ("skill", "agent", "product") for r in content["rankings"][kind])
    assert len(content["rankings"]["skill"]) == 11


def test_empty_batch_never_runs_jev():
    def denied(*args, **kwargs):
        raise AssertionError("empty batch must not invoke jev")
    assert h.judge_rankings([], run_jev=denied, find_jev=denied) == []


def test_duplicate_repo_keeps_per_candidate_decisions_and_metadata(tmp_path, monkeypatch):
    from tests.harvest.test_harvest import setup_main, fixture
    out, _, args = setup_main(tmp_path, monkeypatch)
    skills = fixture("skillleaderboard_catalog.json")["catalog"]
    skills[0]["repo"] = "owner/agent-0"
    monkeypatch.setattr(h, "fetch_skill_leaderboard", lambda: skills)
    def judge(items):
        # Reject only the catalogue entry. The repository entry must not resurrect it.
        return [{**item, "category": "coding", "beginner": 4} for item in items
                if not (item["name"] == "owner/agent-0" and item["source_type"] == "catalog")]
    monkeypatch.setattr(h, "judge_rankings", judge)
    assert h.main(args) == 0
    content = json.loads(out.read_text())
    assert not any(r["name"] == "owner/agent-0" for r in content["rankings"]["skill"])
    row = next(r for r in content["rankings"]["agent"] if r["name"] == "owner/agent-0")
    assert row["source_type"] == "repository"
    assert all(not any(k.startswith("_") for k in r) for kind in ("skill", "agent", "product")
               for r in content["rankings"][kind])
