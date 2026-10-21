import copy
from datetime import date
import json
from pathlib import Path
import subprocess

import pytest

from agentfit.engine.content_pool import load_content, validate
from scripts.harvest import harvest as h

TODAY = date(2026, 10, 21)
FIXTURES = Path(__file__).parent / "fixtures"


def fixture(name):
    return json.loads((FIXTURES / name).read_text())


def test_fetch_sources():
    calls = []
    def fetch(url):
        calls.append(url)
        return fixture("skillleaderboard_catalog.json")
    assert len(h.fetch_skill_leaderboard(fetch)) == 12
    assert calls == ["https://www.skillleaderboard.com/api/catalog"]
    queries = []
    def gh(query):
        queries.append(query)
        return fixture("github_search_agents.json")
    assert len(h.fetch_github_agents(gh, TODAY)) == 48
    assert len(set(queries)) == 4
    for topic, query in zip(("ai-agents", "ai-agent", "coding-agent", "agent-framework"), queries):
        assert f"topic:{topic}" in query
        assert "stars:>1000 archived:false fork:false pushed:>2026-09-21" in query


def test_selection_and_history():
    skills = fixture("skillleaderboard_catalog.json")["catalog"]
    skills += [{**skills[0], "stars": 299}, {**skills[0], "summary": "", "tagline": " "},
               {**skills[0], "repo": "o/tie", "stars7d": 11, "stars": 900}]
    assert [x["repo"] for x in h.select_skills(skills, n=2)] == ["o/tie", "owner/skill-11"]
    agents = fixture("github_search_agents.json")["items"]
    agents += [agents[0], {**agents[0], "full_name": "o/archive", "archived": True},
               {**agents[0], "full_name": "o/fork", "fork": True},
               {**agents[0], "full_name": "o/blank", "description": " "},
               {**agents[0], "full_name": "o/unlicensed", "license": None}]
    history = {"2026-10-14": {"owner/agent-0": 1900, "owner/agent-1": 1900,
                              "owner/agent-2": 2020}, "2026-10-20": {"owner/agent-11": 0}}
    result = h.select_agents(agents, history, today=TODAY)
    assert len(result) == 12
    assert [x["full_name"] for x in result[:4]] == ["owner/agent-1", "owner/agent-0", "owner/agent-2", "owner/agent-11"]
    assert [x["stars7d"] for x in result[:4]] == [110, 100, 0, None]


def test_translation_and_ranking_item():
    calls = []
    def translate(texts):
        calls.append(texts)
        return '["中文一", "中文二"]'
    assert h.translate_zh(["one", "two"], translate) == ["中文一", "中文二"]
    assert calls == [["one", "two"]]
    for raw in ('not JSON', '["only one"]', '["ok", 7]', '["ok", " "]', '{"a": 1}'):
        assert h.translate_zh(["one", "two"], lambda texts: raw) == [None, None]
    def missing(texts):
        raise FileNotFoundError("claude")
    assert h.translate_zh(["one"], missing) == [None]
    item = h.to_ranking_item("Owner/Repo", "https://github.com/Owner/Repo", "English", None, 500, None)
    assert item == {"name": "Owner/Repo", "url": "https://github.com/Owner/Repo",
                    "tagline": {"en": "English", "zh": "English"}, "match": ["repo"],
                    "stars": 500, "stars7d": None}


def test_build_content():
    base = load_content(None)
    before = copy.deepcopy(base)
    item = h.to_ranking_item("o/r", "https://github.com/o/r", "English", "中文", 500, 10)
    result = h.build_content(base, [item], [item], TODAY)
    assert validate(result)
    assert len(result["skills"]) == 24
    assert result["skills"] == base["skills"] and result["tips"] == base["tips"]
    assert base == before
    assert result["rankings"] == {"skill": [item], "agent": [item], "rotate": False,
                                  "source": "The Skill Leaderboard · GitHub", "updated_at": "2026-10-21"}
    assert result["updated_at"] == "2026-10-21"


def setup_main(tmp_path, monkeypatch):
    monkeypatch.setattr(h, "fetch_skill_leaderboard", lambda: fixture("skillleaderboard_catalog.json")["catalog"])
    monkeypatch.setattr(h, "fetch_github_agents", lambda **kw: fixture("github_search_agents.json")["items"])
    out, history = tmp_path / "daily.json", tmp_path / "stars-history.json"
    args = ["--out", str(out), "--history", str(history), "--no-translate"]
    return out, history, args


def test_main_success_and_history_retention(tmp_path, monkeypatch):
    out, history, args = setup_main(tmp_path, monkeypatch)
    history.write_text(json.dumps({"2000-01-01": {"o/r": 1}, date.today().isoformat(): {"o/other": 2}}))
    assert h.main(args) == 0
    data = json.loads(out.read_text())
    assert validate(data) and len(data["rankings"]["skill"]) == 12
    assert not data["rankings"]["rotate"]
    saved = json.loads(history.read_text())
    assert "2000-01-01" not in saved
    assert saved[date.today().isoformat()]["owner/agent-0"] == 2000
    assert all(i["tagline"]["zh"] == i["tagline"]["en"] for i in data["rankings"]["skill"])


@pytest.mark.parametrize("failure", ["skills", "agents", "invalid", "fetch"])
def test_main_abort_writes_nothing(tmp_path, monkeypatch, failure):
    out, history, args = setup_main(tmp_path, monkeypatch)
    out.write_text("previous content")
    history.write_text("{}")
    if failure in ("skills", "agents"):
        name = "fetch_skill_leaderboard" if failure == "skills" else "fetch_github_agents"
        monkeypatch.setattr(h, name, lambda **kw: fixture(
            "skillleaderboard_catalog.json" if failure == "skills" else "github_search_agents.json"
        )["catalog" if failure == "skills" else "items"][:9])
    elif failure == "invalid":
        monkeypatch.setattr(h, "build_content", lambda *args: {})
    else:
        def broken():
            raise OSError("offline")
        monkeypatch.setattr(h, "fetch_skill_leaderboard", broken)
    assert h.main(args) == 3
    assert out.read_text() == "previous content" and history.read_text() == "{}"


def test_subprocess_adapters_are_bounded(monkeypatch):
    calls = []
    def run(args, **kwargs):
        calls.append((args, kwargs))
        return subprocess.CompletedProcess(args, 0, '{"items": []}' if args[0] == "gh" else '["中文"]', '')
    monkeypatch.setattr(h.subprocess, "run", run)
    assert h.subprocess_gh("topic:ai-agents") == {"items": []}
    assert h.subprocess_claude(["English"]) == '["中文"]'
    gh, claude = calls
    assert gh[0][:3] == ["gh", "api", "search/repositories"]
    assert "sort=stars" in gh[0] and "order=desc" in gh[0] and "per_page=50" in gh[0]
    assert any("365aimaster-harvester/0.1" in arg for arg in gh[0])
    assert claude[0][:4] == ["claude", "-p", "--model", "haiku"]
    assert all(call[1]["timeout"] == 30 for call in calls)


def test_http_adapter_headers_and_timeout(monkeypatch):
    import io
    calls = []
    def open_request(request, **kwargs):
        calls.append((request, kwargs))
        return io.BytesIO(b'{"catalog": []}')
    monkeypatch.setattr(h.urllib.request, "urlopen", open_request)
    assert h.urllib_fetch(h.CATALOG_URL) == {"catalog": []}
    request, options = calls[0]
    assert request.get_method() == "GET" and request.full_url == h.CATALOG_URL
    assert request.get_header("User-agent") == h.USER_AGENT
    assert options == {"timeout": 30}


def test_schedule_and_shell_syntax():
    import plistlib
    root = Path(__file__).resolve().parents[2] / "scripts/harvest"
    plist = plistlib.loads((root / "com.365aimaster.harvest.plist").read_bytes())
    assert plist["Label"] == "com.365aimaster.harvest"
    assert plist["StartCalendarInterval"] == {"Hour": 7, "Minute": 30}
    assert plist["StandardOutPath"] == plist["StandardErrorPath"] == "__HOME__/Library/Logs/365aimaster-harvest.log"
    assert plist["ProgramArguments"] == ["__REPO__/scripts/harvest/run_daily.sh", "__REPO__"]
    assert plist["EnvironmentVariables"]["PATH"] == "/opt/homebrew/bin:/usr/local/bin:__HOME__/.local/bin:/usr/bin:/bin"
    for name in ("run_daily.sh", "install_daily.sh"):
        source = (root / name).read_text()
        subprocess.run(["bash", "-n"], input=source, text=True, check=True)
        assert "set -euo pipefail" in source
        assert (root / name).stat().st_mode & 0o111
    daily = (root / "run_daily.sh").read_text()
    assert "git push origin content" in daily
    assert "git pull --ff-only" in daily
    assert "--single-branch --branch content" in daily
    assert "checkout --orphan content" in daily
    assert 'symbolic-ref --short HEAD' in daily
    assert "main" not in daily and "feat/" not in daily


def test_main_uses_summary_when_tagline_is_blank(tmp_path, monkeypatch):
    out, history, args = setup_main(tmp_path, monkeypatch)
    skills = fixture("skillleaderboard_catalog.json")["catalog"]
    skills[0]["tagline"] = " "
    monkeypatch.setattr(h, "fetch_skill_leaderboard", lambda: skills)
    assert h.main(args) == 0
    data = json.loads(out.read_text())
    assert next(item for item in data["rankings"]["skill"] if item["name"] == "owner/skill-0")["tagline"]["en"] == "Useful coding skill 0"


def test_main_translates_both_rankings_in_one_batch(tmp_path, monkeypatch):
    out, history, args = setup_main(tmp_path, monkeypatch)
    calls = []
    def translate(texts):
        calls.append(texts)
        return ["中文"] * len(texts)
    monkeypatch.setattr(h, "translate_zh", translate)
    assert h.main(args[:-1]) == 0
    assert len(calls) == 1 and len(calls[0]) == 24
    data = json.loads(out.read_text())
    assert all(item["tagline"]["zh"] == "中文" for kind in ("skill", "agent") for item in data["rankings"][kind])


def test_main_abort_does_not_create_files(tmp_path, monkeypatch):
    out, history, args = setup_main(tmp_path, monkeypatch)
    monkeypatch.setattr(h, "fetch_skill_leaderboard", lambda: [])
    assert h.main(args) == 3
    assert not out.exists() and not history.exists()
