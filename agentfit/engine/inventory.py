"""Local environment counts; instruction and skill bodies are never read."""
from dataclasses import dataclass, asdict
import json
from pathlib import Path
import stat
import tomllib



@dataclass
class Inventory:
    skills_installed: list[str]
    instructions_bytes: int
    hooks: int
    mcp_servers: int
    subagents: int
    plugins: int

    def to_public(self) -> dict:
        return {**asdict(self), "skills_installed": len(self.skills_installed)}


def _mapping(value) -> dict:
    return value if isinstance(value, dict) else {}


def _config(path: Path, *, toml: bool = False) -> dict:
    # Collector registration imports Inventory; defer the shared path guard.
    from agentfit.engine.collectors._usage import allowed

    if not allowed(path):
        return {}
    try:
        with path.open("rb" if toml else "r") as source:
            return _mapping(tomllib.load(source) if toml else json.load(source))
    except (OSError, ValueError, UnicodeError):
        return {}


def _size(path: Path) -> int:
    try:
        info = path.stat()
        return info.st_size if stat.S_ISREG(info.st_mode) else 0
    except (OSError, ValueError):
        return 0


def _files(root: Path, pattern: str) -> list[Path]:
    result = []
    try:
        for path in root.glob(pattern):
            try:
                if path.is_file():
                    result.append(path)
            except OSError:
                continue
    except OSError:
        pass
    return result


def claude_inventory(home: Path, project_dirs: set[str]) -> Inventory:
    root = home / ".claude"
    skills = _files(root, "skills/*/SKILL.md")
    skills += _files(root, "plugins/cache/*/*/*/skills/*/SKILL.md")
    instructions = [root / "CLAUDE.md"]
    instructions += [Path(project) / "CLAUDE.md" for project in project_dirs]
    settings = _config(root / "settings.json")
    # Only the MCP mapping is used; account data is never inspected or retained.
    mcp = _mapping(_config(home / ".claude.json").get("mcpServers"))
    return Inventory(
        skills_installed=sorted({path.parent.name for path in skills}),
        instructions_bytes=max(_size(path) for path in instructions),
        hooks=len(_mapping(settings.get("hooks"))),
        mcp_servers=len(mcp),
        subagents=len(_files(root, "agents/*.md")),
        plugins=sum(bool(value) for value in _mapping(settings.get("enabledPlugins")).values()),
    )


def codex_inventory(home: Path) -> Inventory:
    root = home / ".codex"
    config = _config(root / "config.toml", toml=True)
    servers = _mapping(config.get("mcp_servers"))
    return Inventory(
        skills_installed=sorted({path.parent.name for path in _files(root, "skills/*/SKILL.md")}),
        instructions_bytes=_size(root / "AGENTS.md"),
        hooks=0,
        mcp_servers=sum(isinstance(value, dict) for value in servers.values()),
        subagents=0,
        plugins=0,
    )
