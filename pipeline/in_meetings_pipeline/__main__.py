"""Entry point: `python -m in_meetings_pipeline run <job.json>`.

Slice 4b: real Hebrew transcription (whisper.cpp ivrit-turbo) of each track + deterministic
post-correction → transcript.json/.txt. Diarization (senko) + intra-track speaker split is 4c.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from .asr import transcribe_track
from .job import Job
from .postcorrect import correct
from .status import Status
from .transcript import merge, segments_from_whisper, to_json, to_text


def load_vocab(directory: Path) -> list[dict]:
    """Context-assembler biasing vocabulary (Phase 2). Absent for now → post-correction is a no-op."""
    p = directory / "context.vocab.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else []


def run(job_path: Path) -> int:
    job = Job.load(job_path)
    status = Status(job.directory, job.meeting_id)
    status.write("queued", 0.0)
    try:
        status.write("transcribing", 0.1)
        tracks: list[list] = []
        if job.mic and job.mic.exists():
            raw = transcribe_track(job.mic, job.directory / "mic.asr")
            tracks.append(segments_from_whisper(raw, "Me"))
        if job.system and job.system.exists():
            raw = transcribe_track(job.system, job.directory / "system.asr")
            tracks.append(segments_from_whisper(raw, "Them"))

        segments = merge(*tracks)
        vocab = load_vocab(job.directory)
        for seg in segments:
            seg.text, _ = correct(seg.text, vocab)

        (job.directory / "transcript.json").write_text(
            json.dumps(to_json(job.meeting_id, job.profile, "he", segments), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        (job.directory / "transcript.txt").write_text(to_text(segments), encoding="utf-8")
        status.outputs["transcript"] = "transcript.json"
        status.outputs["transcript_txt"] = "transcript.txt"
        status.write("done", 1.0)
        return 0
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.decode("utf-8", "replace")[:300] if exc.stderr else str(exc)
        status.write("failed", error=f"whisper-cli failed: {detail}")
        return 1
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
