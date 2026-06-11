"""Entry point: `python -m in_meetings_pipeline run <job.json>`.

Slice 4a wires the bridge end to end with a STUBBED transcribe; real Hebrew transcription
(whisper.cpp + post-correction) lands in slice 4b, diarization in 4c.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from .job import Job
from .status import Status


def transcribe_stub(job: Job) -> dict:
    return {
        "meeting_id": job.meeting_id,
        "profile": job.profile,
        "language": "he",
        "segments": [],
        "note": "stub transcript (slice 4a) — real Hebrew transcription lands in slice 4b",
    }


def run(job_path: Path) -> int:
    job = Job.load(job_path)
    status = Status(job.directory, job.meeting_id)
    status.write("queued", 0.0)
    try:
        status.write("transcribing", 0.1)
        transcript = transcribe_stub(job)
        out = job.directory / "transcript.json"
        out.write_text(json.dumps(transcript, ensure_ascii=False, indent=2), encoding="utf-8")
        status.outputs["transcript"] = out.name
        status.write("done", 1.0)
        return 0
    except Exception as exc:  # noqa: BLE001 — surface any failure as a status the app can show
        status.write("failed", error=str(exc))
        return 1


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] != "run":
        print("usage: python -m in_meetings_pipeline run <job.json>", file=sys.stderr)
        return 2
    return run(Path(argv[2]))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
