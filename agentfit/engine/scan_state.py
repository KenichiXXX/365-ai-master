"""Incremental binary cursors and compact event caches for local logs."""
import json
import os
import tempfile
from datetime import datetime
from hashlib import sha1
from pathlib import Path

from agentfit.engine.events import CompactEvent


class ScanState:
    def __init__(self, path: Path):
        self.path = path
        self.state: dict = {"tools": {}}
        self.issues: dict[str, list[str]] = {}
        try:
            state = json.loads(path.read_text(encoding="utf-8"))
            # Validate persisted cursors before trusting offsets or cached events.
            for files in state["tools"].values():
                for cursor in files.values():
                    if not (0 <= cursor["offset"] <= cursor["size"]):
                        raise ValueError("Invalid cursor")
                    if not isinstance(cursor["head"], str):
                        raise ValueError("Invalid head")
                    for event in cursor["events"]:
                        CompactEvent.from_dict(event).dt()
                    # Prior adapters could retain arguments as skill names. Rebuild
                    # old caches once from the allowlisted source, not legacy text.
                    if cursor.get("adapter_version") != "1":
                        cursor.clear()
                        cursor.update(size=0, offset=0, head=sha1(b"").hexdigest(),
                                      events=[], adapter_version="1")
            self.state = state
        except (OSError, ValueError, TypeError, KeyError, AttributeError):
            pass

    def _cursor(self, tool: str, file: Path) -> dict:
        return self.state["tools"].setdefault(tool, {}).setdefault(
            str(file), {"size": 0, "offset": 0, "head": sha1(b"").hexdigest(), "events": [], "adapter_version": "1"}
        )

    def read_new_lines(self, tool: str, file: Path) -> tuple[list[str], bool]:
        cursor = self._cursor(tool, file)
        with file.open("rb") as stream:
            size = os.fstat(stream.fileno()).st_size
            head = stream.read(min(256, size))
            # Short files grow their head on append: compare only the old prefix.
            previous_head = sha1(head[:min(256, cursor["size"])]).hexdigest()
            reset = size < cursor["size"] or previous_head != cursor["head"]
            offset = 0 if reset else cursor["offset"]
            stream.seek(offset)
            data = stream.read(size - offset)
        complete = data.rfind(b"\n") + 1
        lines = data[:complete].split(b"\n")[:-1]
        cursor.update(size=size, offset=offset + complete, head=sha1(head).hexdigest())
        if reset:
            cursor["events"] = []
            cursor["malformed"] = cursor["skipped"] = 0
        return [line.decode("utf-8", errors="ignore") for line in lines], reset

    def note(self, tool: str, file: Path, kind: str) -> None:
        cursor = self._cursor(tool, file)
        cursor[kind] = cursor.get(kind, 0) + 1

    def issue(self, tool: str, kind: str) -> None:
        self.issues.setdefault(tool, []).append(kind)

    def cached_events(self, tool: str, file: Path) -> list[CompactEvent]:
        cursor = self.state["tools"].get(tool, {}).get(str(file), {})
        return [CompactEvent.from_dict(event) for event in cursor.get("events", [])]

    def set_events(self, tool: str, file: Path, events: list[CompactEvent]) -> None:
        self._cursor(tool, file)["events"] = [event.to_dict() for event in events]

    def files(self, tool: str) -> list[str]:
        return list(self.state["tools"].get(tool, {}))

    def forget_missing(self, tool: str, existing: set[str]) -> None:
        files = self.state["tools"].get(tool, {})
        for file in list(files):
            if file not in existing:
                del files[file]

    def prune_before(self, cutoff: datetime) -> None:
        for files in self.state["tools"].values():
            for cursor in files.values():
                cursor["events"] = [
                    event for event in cursor["events"]
                    if CompactEvent.from_dict(event).dt() >= cutoff
                ]

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=self.path.parent,
                prefix=self.path.name + ".", suffix=".tmp", delete=False,
            ) as stream:
                temporary = Path(stream.name)
                json.dump(self.state, stream, ensure_ascii=False)
            os.replace(temporary, self.path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
