import json
from pathlib import Path
from agentfit.engine.inventory import claude_inventory, codex_inventory

def test_claude_inventory(tmp_path):
    c = tmp_path / ".claude"
    (c / "skills" / "tdd").mkdir(parents=True); (c / "skills" / "tdd" / "SKILL.md").write_text("x")
    (c / "skills" / "empty").mkdir()
    (c / "agents").mkdir(); (c / "agents" / "a.md").write_text("x")
    (c / "CLAUDE.md").write_text("y" * 300)
    (c / "settings.json").write_text(json.dumps({"hooks": {"Stop": [], "PreToolUse": []}, "enabledPlugins": {"p@m": True, "q@m": False}}))
    (tmp_path / ".claude.json").write_text(json.dumps({"mcpServers": {"a": {}, "b": {}}}))
    proj = tmp_path / "proj"; proj.mkdir(); (proj / "CLAUDE.md").write_text("z" * 900)
    inv = claude_inventory(tmp_path, {str(proj)})
    assert inv.skills_installed == ["tdd"]
    assert (inv.instructions_bytes, inv.hooks, inv.mcp_servers, inv.subagents, inv.plugins) == (900, 2, 2, 1, 1)
    assert set(inv.to_public()) == {"skills_installed", "instructions_bytes", "hooks", "mcp_servers", "subagents", "plugins"}
    assert inv.to_public()["skills_installed"] == 1

def test_codex_inventory(tmp_path):
    x = tmp_path / ".codex"; (x / "skills" / "s1").mkdir(parents=True); (x / "skills" / "s1" / "SKILL.md").write_text("x")
    (x / "AGENTS.md").write_text("a" * 250)
    (x / "config.toml").write_text('[mcp_servers.one]\ncommand="a"\n[mcp_servers.two]\ncommand="b"\n')
    inv = codex_inventory(tmp_path)
    assert (inv.skills_installed, inv.instructions_bytes, inv.mcp_servers) == (["s1"], 250, 2)

def test_missing_everything(tmp_path):
    inv = claude_inventory(tmp_path, set())
    assert inv.to_public() == {"skills_installed": 0, "instructions_bytes": 0, "hooks": 0, "mcp_servers": 0, "subagents": 0, "plugins": 0}


def test_plugins_dedup_and_metadata_only(tmp_path, monkeypatch):
    c = tmp_path / ".claude"
    for relative in ("skills/z", "skills/a", "plugins/cache/market/plugin/1/skills/z",
                     "plugins/cache/market/plugin/2/skills/b"):
        skill = c / relative
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("private skill body")
    (c / "CLAUDE.md").write_text("字" * 200)
    (c / "agents").mkdir()
    (c / "agents/a.md").write_text("private agent body")
    (c / "agents/not-a-file.md").mkdir()
    x = tmp_path / ".codex"
    x.mkdir()
    (x / "AGENTS.md").write_text("x" * 400)
    original = Path.open
    def guarded(path, *args, **kwargs):
        assert path.suffix != ".md", "metadata only"
        return original(path, *args, **kwargs)
    monkeypatch.setattr(Path, "open", guarded)
    inv = claude_inventory(tmp_path, {str(tmp_path / "missing")})
    assert inv.skills_installed == ["a", "b", "z"]
    assert inv.instructions_bytes == 600 and inv.subagents == 1
    assert all(isinstance(v, int) for v in inv.to_public().values())
    assert codex_inventory(tmp_path).instructions_bytes == 400


def test_invalid_config_fields_and_missing_codex(tmp_path):
    assert not any(codex_inventory(tmp_path).to_public().values())
    c = tmp_path / ".claude"; c.mkdir()
    x = tmp_path / ".codex"; x.mkdir()
    for raw in ('{broken', '[]', '{"hooks": [1], "enabledPlugins": "bad"}'):
        (c / "settings.json").write_text(raw)
        (tmp_path / ".claude.json").write_text(raw)
        assert not any(claude_inventory(tmp_path, set()).to_public().values())
    for raw in ('[broken', 'mcp_servers = [1, 2]', '[mcp_servers]\none = 1\n[mcp_servers.valid]\ncommand="a"'):
        (x / "config.toml").write_text(raw)
        assert codex_inventory(tmp_path).mcp_servers == (1 if 'valid' in raw else 0)
    (c / "settings.json").write_bytes(b"\xff")
    assert claude_inventory(tmp_path, set()).hooks == 0


def test_unreadable_settings_preserve_other_fields(tmp_path, monkeypatch):
    c = tmp_path / ".claude"; c.mkdir()
    (c / "CLAUDE.md").write_text("x" * 100)
    original = Path.open
    def guarded(path, *args, **kwargs):
        if path.name == "settings.json":
            raise PermissionError("unreadable")
        return original(path, *args, **kwargs)
    monkeypatch.setattr(Path, "open", guarded)
    inv = claude_inventory(tmp_path, set())
    assert inv.instructions_bytes == 100 and inv.hooks == 0 and inv.plugins == 0


def test_collectors_delegate_inventory(tmp_path):
    from agentfit.engine.collectors.claude_code import ClaudeCodeCollector
    from agentfit.engine.collectors.codex import CodexCollector

    project = tmp_path / "project"; project.mkdir()
    (project / "CLAUDE.md").write_text("p" * 800)
    assert ClaudeCodeCollector().inventory(tmp_path, {str(project)}) == claude_inventory(tmp_path, {str(project)})
    assert ClaudeCodeCollector().inventory(tmp_path) == claude_inventory(tmp_path, set())
    assert CodexCollector().inventory(tmp_path) == codex_inventory(tmp_path)
