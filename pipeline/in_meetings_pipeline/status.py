"""Status the pipeline writes back for the Swift app to watch (ADR-009 shared schema).

Written atomically (tmp + os.replace) so the app never reads a half-written file.
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path

PHASES = ("queued", "transcribing", "diarizing", "packaging", "done", "failed")


class Status:
    def __init__(self, directory: Path, meeting_id: str):
        self.path = Path(directory) / "status.json"
        self.meeting_id = meeting_id
        self.outputs: dict[str, str] = {}

    def write(self, phase: str, progress: float = 0.0, error: str | None = None) -> None:
        assert phase in PHASES, f"unknown phase {phase!r}"
        payload = {
            "meeting_id": self.meeting_id,
            "phase": phase,
            "progress": progress,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "error": error,
            "outputs": self.outputs,
        }
        tmp = self.path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(tmp, self.path)
