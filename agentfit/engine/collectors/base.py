"""Shared collector contract and opt-in registry."""
from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING, Protocol

from agentfit.engine.events import CompactEvent
from agentfit.engine.scan_state import ScanState

if TYPE_CHECKING:
    from agentfit.engine.inventory import Inventory


class Collector(Protocol):
    tool: str
    tier: str
    # Adapter 1 coverage is defined centrally in coverage.py.

    def detect(self, home: Path) -> bool: ...

    def scan(self, home: Path, state: ScanState) -> list[CompactEvent]:
        """Return all cached and new events."""
        ...

    def inventory(self, home: Path) -> Inventory | None: ...


REGISTRY: list[Collector] = []


def register(c: Collector) -> Collector:
    REGISTRY.append(c)
    return c
