from pathlib import Path
from datetime import datetime, timezone, timedelta
from agentfit.engine.scan_state import ScanState
from agentfit.engine.events import CompactEvent

def test_incremental_reads_only_new_complete_lines(tmp_path):
    log = tmp_path / "a.jsonl"; log.write_text('{"a":1}\n{"b":2}\n{"partial"')
    st = ScanState(tmp_path / "state.json")
    lines, reset = st.read_new_lines("t", log)
    assert lines == ['{"a":1}', '{"b":2}'] and reset is False
    with open(log, "a") as f: f.write(':3}\n{"c":4}\n')
    lines, _ = st.read_new_lines("t", log)
    assert lines == ['{"partial":3}', '{"c":4}']

def test_truncated_file_resets(tmp_path):
    log = tmp_path / "a.jsonl"; log.write_text('{"a":1}\n{"b":2}\n')
    st = ScanState(tmp_path / "s.json"); st.read_new_lines("t", log)
    log.write_text('{"z":9}\n')
    lines, reset = st.read_new_lines("t", log)
    assert reset is True and lines == ['{"z":9}']

def test_events_persist_and_prune(tmp_path):
    p = tmp_path / "s.json"; log = tmp_path / "a.jsonl"; log.write_text("x\n")
    st = ScanState(p); st.read_new_lines("t", log)
    old = (datetime.now(timezone.utc) - timedelta(days=40)).isoformat()
    new = datetime.now(timezone.utc).isoformat()
    st.set_events("t", log, [CompactEvent(tool="t", key="1", ts=old, model="m"),
                             CompactEvent(tool="t", key="2", ts=new, model="m")])
    st.prune_before(datetime.now(timezone.utc) - timedelta(days=30)); st.save()
    again = ScanState(p)
    assert [e.key for e in again.cached_events("t", log)] == ["2"]

def test_corrupt_state_file_starts_empty(tmp_path):
    p = tmp_path / "s.json"; p.write_text("{not json")
    assert ScanState(p).files("t") == []


def test_short_file_append_keeps_cache_and_resumes_after_reload(tmp_path):
    log = tmp_path / "a.jsonl"
    log.write_bytes("你好\n".encode() + b"partial")
    st = ScanState(tmp_path / "state.json")
    assert st.read_new_lines("t", log) == (["你好"], False)
    event = CompactEvent(tool="t", key="1", ts="2026-10-21T00:00:00Z", model="m")
    st.set_events("t", log, [event])
    st.save()
    again = ScanState(st.path)
    with log.open("ab") as stream:
        stream.write(b" complete\n" + b"x" * 300 + b"\n")
    assert again.read_new_lines("t", log) == (["partial complete", "x" * 300], False)
    assert again.cached_events("t", log) == [event]
    assert again.read_new_lines("t", log) == ([], False)


def test_same_size_head_rewrite_resets_and_clears_cache(tmp_path):
    log = tmp_path / "a.jsonl"
    log.write_text("a" * 300 + "\n")
    st = ScanState(tmp_path / "s.json")
    st.read_new_lines("t", log)
    st.set_events("t", log, [CompactEvent("t", "1", "2026-10-21", "m")])
    log.write_text("b" * 300 + "\n")
    assert st.read_new_lines("t", log) == (["b" * 300], True)
    assert st.cached_events("t", log) == []


def test_forget_missing_is_tool_specific(tmp_path):
    log = tmp_path / "a.jsonl"
    log.write_text("x\n")
    st = ScanState(tmp_path / "s.json")
    for tool in ("a", "b"):
        st.read_new_lines(tool, log)
    st.forget_missing("a", {str(log)})
    assert st.files("a") == [str(log)]
    st.forget_missing("a", set())
    assert st.files("a") == []
    assert st.files("b") == [str(log)]


def test_invalid_state_shapes_start_empty(tmp_path):
    p = tmp_path / "s.json"
    for raw in ('null', '[]', '{"tools": []}', '{"tools": {"t": {"f": {}}}}'):
        p.write_text(raw)
        assert ScanState(p).files("t") == []


def test_event_roundtrip_and_aware_dates():
    event = CompactEvent("t", "1", "2026-10-21T12:00:00+09:00", "m", tool_calls={"Edit": 2})
    assert CompactEvent.from_dict({**event.to_dict(), "future_field": 1}) == event
    assert event.dt().utcoffset() == timedelta(hours=9)
    for ts in ("2026-10-21T03:00:00Z", "2026-10-21T03:00:00"):
        assert CompactEvent("t", "1", ts, "m").dt() == event.dt()
    event.to_dict()["tool_calls"]["Edit"] = 99
    assert event.tool_calls == {"Edit": 2}
    assert CompactEvent("t", "2", event.ts, "m").tool_calls == {}


def test_atomic_save_preserves_previous_state_on_replace_failure(tmp_path, monkeypatch):
    import pytest
    import agentfit.engine.scan_state as module

    path = tmp_path / "nested" / "state.json"
    st = ScanState(path)
    st.save()
    previous = path.read_bytes()

    def fail_replace(source, destination):
        assert Path(source).parent == path.parent
        raise OSError("replace failed")

    monkeypatch.setattr(module.os, "replace", fail_replace)
    with pytest.raises(OSError, match="replace failed"):
        st.save()
    assert path.read_bytes() == previous
    assert list(path.parent.iterdir()) == [path]


def test_collector_registration_returns_instance(monkeypatch):
    from agentfit.engine.collectors import base

    monkeypatch.setattr(base, "REGISTRY", [])

    class ExampleCollector:
        tool = "example"
        tier = "usage"

        def detect(self, home): return False
        def scan(self, home, state): return []
        def inventory(self, home): return None

    collector = ExampleCollector()
    assert base.register(collector) is collector
    assert base.REGISTRY == [collector]
