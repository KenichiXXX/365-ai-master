import json
from datetime import datetime, timedelta, timezone

from agentfit.engine.practice import PracticeLedger, compatible
from agentfit.engine.events import CompactEvent
from agentfit.engine.content_pool import load_content

NOW = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)
CARD = next(c for c in load_content(None)["skills"] if c["id"] == "web_search")
COVERAGE = {"claude_code": {"adapter_version": "1", "format": "claude-jsonl-v1",
    "status": "ok", "signals": {"tool_calls": "available"}}}


def event(key, at=NOW, **kw):
    return CompactEvent("claude_code", key, at.isoformat(), "", **kw)


def ledger(tmp_path):
    return PracticeLedger({}, NOW)


def test_view_is_not_start_and_baseline_backfill_replay(tmp_path):
    book = ledger(tmp_path)
    old = event("old", NOW - timedelta(seconds=1), tool_calls={"WebSearch": 1})
    book.observe([old], [CARD], COVERAGE, NOW)
    assert book.attempts == []
    attempt = book.start(CARD, "action", NOW)
    book.observe([old, event("late", NOW - timedelta(seconds=2), tool_calls={"WebSearch": 1})], [CARD], COVERAGE, NOW)
    assert attempt["first_observed_at"] is None
    new = event("new", NOW + timedelta(seconds=1), tool_calls={"WebSearch": 1})
    book.observe([new], [CARD], COVERAGE, NOW + timedelta(seconds=2))
    assert attempt["first_observed_at"] == new.ts
    assert attempt["reuse_dates"] == []
    book.observe([new], [CARD], COVERAGE, NOW + timedelta(days=1))
    assert attempt["reuse_dates"] == []
    assert len(book.state["events"]) == 3
    encoded = json.dumps(book.state)
    assert '"key"' not in encoded and '"tool_calls"' not in encoded
    assert all(len(key) == 64 for key in book.state["events"])


def test_newest_attempt_owns_event_and_reuse_requires_capability(tmp_path):
    book = ledger(tmp_path)
    first = book.start(CARD, "first", NOW)
    second = book.start(CARD, "second", NOW + timedelta(seconds=1))
    book.observe([event("new", NOW + timedelta(seconds=2), tool_calls={"WebSearch": 1})], [CARD], COVERAGE, NOW + timedelta(seconds=3))
    assert first["first_observed_at"] is None
    assert second["first_observed_at"] is not None
    book.observe([event("usage", NOW + timedelta(days=1), input=50)], [CARD], COVERAGE, NOW + timedelta(days=1))
    assert second["reuse_dates"] == []
    book.observe([event("reuse", NOW + timedelta(days=1), tool_calls={"WebSearch": 1})], [CARD], COVERAGE, NOW + timedelta(days=1))
    assert len(second["reuse_dates"]) == 1
    book.stop(second["attempt_id"])
    book.observe([event("stopped", NOW + timedelta(days=2), tool_calls={"WebSearch": 1})], [CARD], COVERAGE, NOW + timedelta(days=2))
    assert len(second["reuse_dates"]) == 1


def test_self_configuration_versions_and_future(tmp_path):
    book = ledger(tmp_path)
    self_card = next(c for c in load_content(None)["skills"] if c["id"] == "init_cmd")
    attempt = book.start(self_card, "self", NOW)
    book.self_report(self_card, NOW)
    assert attempt["self_reported_at"] == NOW.isoformat()
    assert attempt["first_observed_at"] is None
    assert not compatible(CARD, {"claude_code": {**COVERAGE["claude_code"], "adapter_version": "99"}})
    book.start(CARD, "future", NOW)
    book.observe([event("future", NOW + timedelta(days=1), tool_calls={"WebSearch": 1})], [CARD], COVERAGE, NOW)
    assert not book.state["events"]


def test_same_day_assignment_survives_lighting_download_restart(tmp_path):
    from agentfit.engine.codex_book import update_book, mark_tried
    from agentfit.engine.profile import Profile
    content = load_content(None)
    path = tmp_path / "progress.json"
    first = update_book(content, Profile(now=NOW), {}, path, NOW)["today"]
    assert mark_tried("init_cmd", path, NOW)
    content["updated_at"] = "next-revision"
    content["skills"].reverse()
    again = update_book(content, Profile(now=NOW), {}, path, NOW)["today"]
    assert again["id"] == first["id"]
    assert again["content_revision"] == first["content_revision"]
    assert again["prompt"] == first["prompt"]


def test_seen_fallback_skip_and_legacy_migration_twice(tmp_path):
    from agentfit.engine.codex_book import update_book
    from agentfit.engine.profile import Profile
    content = load_content(None)
    path = tmp_path / "progress.json"
    legacy = {c["id"]: {"at": "before", "how": "log"} for c in content["skills"]}
    path.write_text(json.dumps({"lit": legacy, "badges": ["book_all"]}))
    for _ in range(2):
        book = update_book(content, Profile(now=NOW), {}, path, NOW)
        assert book["today"]["mode"] == "review"
        assert book["today"]["id"].startswith("review_")
        assert all(c["evidence_kind"] == "historical" for c in book["cards"])
    saved = json.loads(path.read_text())
    assert saved["lit"] == legacy and saved["badges"] == ["book_all"]
    assert saved["practice"]["attempts"] == []


def test_copy_start_self_and_yesterday_cli(tmp_path, capsys):
    from agentfit.engine.snapshot import build_snapshot
    from agentfit.engine.__main__ import main
    build_snapshot(tmp_path / "home", tmp_path, "en", NOW, enabled=set())
    assert main(["practice", "init_cmd", "start", "--state-dir", str(tmp_path)]) == 0
    assert main(["mark-tried", "init_cmd", "--state-dir", str(tmp_path)]) == 0
    saved = json.loads((tmp_path / "progress.json").read_text())
    attempt = saved["practice"]["attempts"][0]
    assert attempt["started_at"] and attempt["self_reported_at"]
    assert attempt["first_observed_at"] is None
    assert main(["practice", "unknown", "start", "--state-dir", str(tmp_path)]) == 0
    assert json.loads(capsys.readouterr().out.splitlines()[-1]) == {"ok": False}


def test_yesterday_reports_no_new_data_and_stop(tmp_path):
    from agentfit.engine.codex_book import update_book, practice_command
    from agentfit.engine.profile import Profile
    path = tmp_path / "progress.json"
    content = load_content(None)
    update_book(content, Profile(now=NOW), {}, path, NOW, coverage=COVERAGE)
    practice_command("web_search", "start", path, NOW)
    tomorrow = NOW + timedelta(days=1)
    book = update_book(content, Profile(now=tomorrow), {}, path, tomorrow, coverage=COVERAGE)
    assert book["yesterday"][0]["status"] == "coverage_missing"
    practice_command(book["yesterday"][0]["attempt_id"], "stop", path, tomorrow)
    assert update_book(content, Profile(now=tomorrow), {}, path, tomorrow)["yesterday"] == []


def test_skip_once_and_incompatible_review(tmp_path):
    from agentfit.engine.codex_book import update_book, practice_command
    from agentfit.engine.profile import Profile
    path = tmp_path / "progress.json"
    content = load_content(None)
    first = update_book(content, Profile(now=NOW), {}, path, NOW)["today"]
    assert practice_command(first["id"], "skip", path, NOW)
    second = update_book(content, Profile(now=NOW), {}, path, NOW)["today"]
    assert first["id"] != second["id"]
    assert not practice_command(second["id"], "skip", path, NOW)
    incompatible = {"claude_code": {**COVERAGE["claude_code"], "adapter_version": "99"}}
    assert update_book(content, Profile(now=NOW), {}, tmp_path / "incompatible.json", NOW,
                       coverage=incompatible)["today"] is None


def test_configuration_is_separate_and_kept_without_observation(tmp_path):
    from agentfit.engine.codex_book import update_book
    from agentfit.engine.profile import Profile
    from agentfit.engine.inventory import Inventory
    path = tmp_path / "progress.json"
    book = update_book(load_content(None), Profile(now=NOW),
                       {"claude_code": Inventory([], 201, 0, 0, 0, 0)}, path, NOW)
    card = next(c for c in book["cards"] if c["id"] == "rules_file")
    assert card["evidence_kind"] == "configuration"
    saved = json.loads(path.read_text())
    assert saved["practice"]["configurations"]["rules_file"]["kind"] == "configuration"
    assert saved["practice"]["attempts"] == []
    book = update_book(load_content(None), Profile(now=NOW), {}, path, NOW)
    assert next(c for c in book["cards"] if c["id"] == "rules_file")["evidence_kind"] == "configuration"


def test_action_copy_tracks_the_selected_action_id(tmp_path):
    from agentfit.engine.snapshot import build_snapshot
    from agentfit.engine.codex_book import practice_command
    snapshot = build_snapshot(tmp_path / "home", tmp_path, "en", NOW, enabled=set())
    action_id = snapshot["today_tip"]["action_id"]
    assert practice_command(action_id, "copy", tmp_path / "progress.json", NOW)
    attempt = json.loads((tmp_path / "progress.json").read_text())["practice"]["attempts"][0]
    assert attempt["action_id"] == action_id


def test_snapshot_observation_reuse_and_privacy(tmp_path):
    from agentfit.engine.snapshot import build_snapshot
    from agentfit.engine.codex_book import practice_command
    home, state = tmp_path / "home", tmp_path / "state"
    log = home / ".claude/projects/synthetic/log.jsonl"
    log.parent.mkdir(parents=True)
    def append(key, at, capability=True):
        row = {"type": "assistant", "timestamp": at.isoformat(), "cwd": "/private-sentinel",
               "message": {"id": key, "model": "claude-sonnet-5", "usage": {"input_tokens": 10, "output_tokens": 2},
                           "content": [{"type": "tool_use", "id": key, "name": "WebSearch",
                                        "input": {"query": "secret-sentinel"}}] if capability else []}}
        with log.open("a") as stream:
            stream.write(json.dumps(row) + "\n")
    append("old", NOW - timedelta(seconds=1))
    build_snapshot(home, state, "en", NOW)
    assert practice_command("web_search", "copy", state / "progress.json", NOW)
    append("new", NOW + timedelta(seconds=1))
    result = build_snapshot(home, state, "en", NOW + timedelta(seconds=2))
    card = lambda snap: next(c for c in snap["book"]["cards"] if c["id"] == "web_search")
    assert card(result)["evidence_kind"] == "log_observed"
    tomorrow = NOW + timedelta(days=1)
    append("usage-only", tomorrow, False)
    result = build_snapshot(home, state, "en", tomorrow)
    assert card(result)["evidence_kind"] == "log_observed"
    assert result["book"]["yesterday"][0]["status"] == "observed"
    append("reuse", tomorrow + timedelta(seconds=1))
    result = build_snapshot(home, state, "en", tomorrow + timedelta(seconds=2))
    assert card(result)["evidence_kind"] == "reuse"
    saved = json.loads((state / "progress.json").read_text())
    assert len(saved["practice"]["attempts"][0]["reuse_dates"]) == 1
    for raw in (json.dumps(result), json.dumps(saved["practice"])):
        assert "secret-sentinel" not in raw and "/private-sentinel" not in raw and str(home) not in raw


def test_late_post_start_event_is_not_an_earlier_reuse_date(tmp_path):
    book = ledger(tmp_path)
    attempt = book.start(CARD, "one", NOW)
    book.observe([event("observed", NOW + timedelta(days=1), tool_calls={"WebSearch": 1})], [CARD], COVERAGE, NOW + timedelta(days=1))
    book.observe([event("late", NOW + timedelta(seconds=1), tool_calls={"WebSearch": 1})], [CARD], COVERAGE, NOW + timedelta(days=2))
    assert attempt["reuse_dates"] == []


def test_missing_signal_never_verifies_and_can_be_self_reported(tmp_path):
    from agentfit.engine.codex_book import update_book, mark_tried
    from agentfit.engine.profile import Profile
    path = tmp_path / "progress.json"
    unsupported = {"claude_code": {**COVERAGE["claude_code"], "signals": {"tool_calls": "unsupported"}}}
    update_book(load_content(None), Profile(now=NOW), {}, path, NOW, coverage=unsupported)
    book = PracticeLedger(json.loads(path.read_text()), NOW)
    attempt = book.start(CARD, "unsupported", NOW)
    book.observe([event("unsupported", NOW + timedelta(seconds=1), tool_calls={"WebSearch": 1})], [CARD], unsupported, NOW + timedelta(seconds=2))
    assert attempt["first_observed_at"] is None
    assert mark_tried("web_search", path, NOW)
    result = update_book(load_content(None), Profile(now=NOW), {}, path, NOW, coverage=unsupported)
    assert next(c for c in result["cards"] if c["id"] == "web_search")["evidence_kind"] == "self_reported"


def test_self_report_alone_does_not_start_an_attempt(tmp_path):
    book = ledger(tmp_path)
    card = next(c for c in load_content(None)["skills"] if c["id"] == "init_cmd")
    assert book.self_report(card, NOW)
    assert book.attempts == []
    assert book.evidence(card["id"]) == "self_reported"


def test_reuse_across_explicit_attempts(tmp_path):
    book = ledger(tmp_path)
    book.start(CARD, "first", NOW)
    book.observe([event("first", NOW + timedelta(seconds=1), tool_calls={"WebSearch": 1})], [CARD], COVERAGE, NOW + timedelta(seconds=2))
    second = book.start(CARD, "second", NOW + timedelta(days=1))
    book.observe([event("second", NOW + timedelta(days=1, seconds=1), tool_calls={"WebSearch": 1})], [CARD], COVERAGE, NOW + timedelta(days=1, seconds=2))
    assert len(second["reuse_dates"]) == 1
    assert book.evidence(CARD["id"]) == "reuse"


def test_one_event_cannot_validate_two_similar_skills(tmp_path):
    book = ledger(tmp_path)
    similar = {**CARD, "id": "similar"}
    first = book.start(CARD, "first", NOW)
    second = book.start(similar, "second", NOW)
    book.observe([event("single", NOW + timedelta(seconds=1), tool_calls={"WebSearch": 1})], [CARD, similar], COVERAGE, NOW + timedelta(seconds=2))
    assert first["first_observed_at"] is None
    assert second["first_observed_at"] is not None


def test_empty_compatible_exercise_pool_still_produces_snapshot(tmp_path):
    from agentfit.engine.snapshot import build_snapshot
    content = load_content(None)
    content["skills"] = []
    content["review_exercises"] = []
    file = tmp_path / "content.json"
    file.write_text(json.dumps(content))
    result = build_snapshot(tmp_path / "home", tmp_path / "state", "en", NOW, enabled=set(), content=file)
    assert result["book"]["today"] is None
