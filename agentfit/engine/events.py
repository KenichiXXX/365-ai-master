"""Compact internal events; serialization is for the local cache, not snapshots."""
from dataclasses import asdict, dataclass, field, fields
from datetime import datetime, timezone


@dataclass
class CompactEvent:
    tool: str
    key: str
    ts: str
    model: str
    input: int = 0
    output: int = 0
    cache_read: int = 0
    cache_write: int = 0
    tool_calls: dict[str, int] = field(default_factory=dict)
    skill_calls: dict[str, int] = field(default_factory=dict)
    sidechain: bool = False
    effort: str | None = None
    turn_start: int = 0
    aborted: int = 0
    compacted: int = 0
    hook_success: int = 0
    markers: dict[str, str] = field(default_factory=dict)
    cwd: str | None = None  # Internal only; never include in public snapshots.

    def to_dict(self) -> dict:
        return asdict(self)

    @staticmethod
    def from_dict(d: dict) -> "CompactEvent":
        return CompactEvent(**{f.name: d[f.name] for f in fields(CompactEvent) if f.name in d})

    def dt(self) -> datetime:
        value = datetime.fromisoformat(self.ts.replace("Z", "+00:00"))
        return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
