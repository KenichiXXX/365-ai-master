"""Local environment counts; instruction and skill bodies are never read."""
import json
import stat
import tomllib
from dataclasses import asdict, dataclass, field
from pathlib import Path


@dataclass
class Inventory:
    skills_installed: list[str]
    instructions_bytes: int
    hooks: int
    mcp_servers: int | None
    subagents: int
    plugins: int
    plugins_installed: list[str] = field(default_factory=list)

    def to_public(self) -> dict:
        public = asdict(self)
        public.pop("plugins_installed")
        public["skills_installed"] = len(self.skills_installed)
        return public


def _mapping(value) -> dict:
    return value if isinstance(value, dict) else {}


def _config(path: Path, *, toml: bool = False) -> dict:
    # Collector registration imports Inventory; defer the shared path guard.
    from agentfit.engine.collectors._usage import allowed

    fields = {"settings.json": {"hooks", "enabledPlugins"}, "config.toml": {"mcp_servers"}}
    if path.name not in fields or not allowed(path, path.parent):
        return {}
    try:
        with path.open("rb" if toml else "r") as source:
            config = _mapping(tomllib.load(source) if toml else json.load(source))
            return {key: value for key, value in config.items() if key in fields[path.name]}
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
                from agentfit.engine.collectors._usage import allowed
                if allowed(path, root) and path.is_file():
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
    from agentfit.engine.collectors._usage import allowed, identifier
    settings = _config(root / "settings.json") if allowed(root, home) else {}
    # MCP data is unavailable: its mixed account configuration is never opened.
    return Inventory(
        skills_installed=sorted({path.parent.name for path in skills if identifier(path.parent.name)}),
        instructions_bytes=max(_size(path) for path in instructions),
        hooks=len(_mapping(settings.get("hooks"))),
        mcp_servers=None,
        subagents=len(_files(root, "agents/*.md")),
        plugins=sum(bool(value) for value in _mapping(settings.get("enabledPlugins")).values()),
        plugins_installed=sorted({name.split("@", 1)[0] for name, value
                                  in _mapping(settings.get("enabledPlugins")).items() if value and identifier(name.split("@", 1)[0])}),
    )


def codex_inventory(home: Path) -> Inventory:
    root = home / ".codex"
    from agentfit.engine.collectors._usage import allowed, identifier
    config = _config(root / "config.toml", toml=True) if allowed(root, home) else {}
    servers = _mapping(config.get("mcp_servers"))
    return Inventory(
        skills_installed=sorted({path.parent.name for path in _files(root, "skills/*/SKILL.md") if identifier(path.parent.name)}),
        instructions_bytes=_size(root / "AGENTS.md"),
        hooks=0,
        mcp_servers=sum(isinstance(value, dict) for value in servers.values()),
        subagents=0,
        plugins=0,
    )
