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
    # Record-time facts from the recorder (Swift); optional so older jobs still load (ADR-005).
    started_at: str | None = None  # ISO-8601 wall-clock meeting start
    ended_at: str | None = None  # ISO-8601 wall-clock meeting end
    sample_rate: int | None = None
    capture_source_app: str | None = None  # detected call app (ADR-001/P3); None for in-person
    video: bool = False  # whether a video.mov was captured (V1)

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
            started_at=data.get("started_at"),
            ended_at=data.get("ended_at"),
            sample_rate=data.get("sample_rate"),
            capture_source_app=data.get("capture_source_app"),
            video=bool(data.get("video", False)),
        )
