"""The job contract: what the Swift app hands the pipeline (ADR-009 shared schema)."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Job:
    meeting_id: str
    directory: Path
    profile: str  # "call" | "inPerson"
    mic: Path | None
    system: Path | None

    @classmethod
    def load(cls, path: Path) -> Job:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        directory = Path(data["directory"])
        tracks = data.get("tracks", {})
        mic = directory / tracks["mic"] if tracks.get("mic") else None
        system = directory / tracks["system"] if tracks.get("system") else None
        return cls(
            meeting_id=data["meeting_id"],
            directory=directory,
            profile=data.get("profile", "call"),
            mic=mic,
            system=system,
        )
