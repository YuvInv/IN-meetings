"""Entry point: `python -m in_meetings_pipeline run <job.json>`.

Per-meeting worker: transcribe each track (whisper.cpp ivrit-turbo, slice 4b) → diarize + attribute
speakers (senko, slice 4c) → deterministic post-correction → transcript.json/.txt.

Speaker attribution is profile-aware (ADR-003/011):
- call (dual-track): the mic is the known IN partner ("Me"); diarize the *system* track to split the
  remote side ("Them" if one person, else "Speaker 1…N").
- in-person (mic-only): everyone shares the mic → diarize it into "Speaker 1…N".
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from .asr import ENGINE, is_silent, model_revision, transcribe_track
from .context_assembler import assemble
from .diarize import SpeakerTurn, diarize_track, label_track
from .job import Job
from .metadata import build_metadata
from .postcorrect import correct
from .status import Status
from .transcript import Segment, merge, segments_from_whisper, to_json, to_text


def load_vocab(directory: Path) -> list[dict]:
    """Context-assembler biasing vocabulary (Phase 2). Absent for now → post-correction is a no-op."""
    p = directory / "context.vocab.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else []


def load_user_vocab() -> list[dict]:
    """User-taught corrections from the dashboard's find-&-replace "remember this" toggle, applied to
    EVERY meeting. Written by the macOS app as ``[{"canonical": ..., "variants": [...]}]``. Path: the
    ``IN_MEETINGS_VOCAB_CORRECTIONS`` env override (kept in sync with the app's ``VocabStore``), else the
    app's Application Support file. Absent/unreadable → no user corrections (stays a no-op).
    """
    env = os.environ.get("IN_MEETINGS_VOCAB_CORRECTIONS")
    p = (
        Path(env)
        if env
        else Path.home() / "Library/Application Support/IN Meetings/vocab-corrections.json"
    )
    if not p.exists():
        return []
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    return data if isinstance(data, list) else []


def merge_vocab(base: list[dict], extra: list[dict]) -> list[dict]:
    """Merge two vocab lists by canonical, unioning variants (order-stable; ``base`` entries first)."""
    merged: list[dict] = []
    index: dict[str, dict] = {}
    for entry in [*base, *extra]:
        if not isinstance(entry, dict):
            continue
        canon = entry.get("canonical")
        if not canon:
            continue
        variants = [v for v in entry.get("variants", []) if v]
        if canon in index:
            for v in variants:
                if v not in index[canon]["variants"]:
                    index[canon]["variants"].append(v)
        else:
            new = {"canonical": canon, "variants": list(variants)}
            index[canon] = new
            merged.append(new)
    return merged


def _safe_turns(wav: Path) -> list[SpeakerTurn]:
    """Diarize a track, degrading to no turns on failure — diarization is an enhancement, not a gate."""
    try:
        return diarize_track(wav)
    except Exception as exc:  # noqa: BLE001 — coarse labels beat failing the whole transcript
        print(f"diarization skipped ({type(exc).__name__}: {exc})", file=sys.stderr)
        return []


def attribute_speakers(
    job: Job, mic_segs: list[Segment], system_segs: list[Segment]
) -> tuple[list[Segment], list[dict], bool]:
    """Diarize the right track(s) for the profile and return (segments, speakers, diarized)."""
    speakers: list[dict] = []
    out: list[Segment] = []
    diarized = False

    if job.profile == "inPerson":
        turns = _safe_turns(job.mic) if (job.mic and job.mic.exists()) else []
        labeled, spk = label_track(mic_segs, turns, side="unknown", track="mic")
        out += labeled
        speakers += spk
        diarized = bool(turns)
    else:  # call
        if mic_segs:
            out += mic_segs
            speakers.append({"id": "Me", "side": "internal", "track": "mic"})
        if system_segs:  # empty when the remote track was silent/skipped → no fabricated "Them"
            turns = _safe_turns(job.system) if (job.system and job.system.exists()) else []
            labeled, spk = label_track(
                system_segs, turns, side="external", track="system", solo_label="Them"
            )
            out += labeled
            speakers += spk
            diarized = bool(turns)

    return merge(out), speakers, diarized


def run(job_path: Path) -> int:
    job = Job.load(job_path)
    status = Status(job.directory, job.meeting_id)
    status.write("queued", 0.0)
    try:
        ctx = assemble(job.directory)
        status.write("transcribing", 0.1)
        mic_segs: list[Segment] = []
        system_segs: list[Segment] = []
        if job.mic and job.mic.exists() and not is_silent(job.mic):
            base = "Speaker 1" if job.profile == "inPerson" else "Me"
            raw = transcribe_track(job.mic, job.directory / "mic.asr")
            mic_segs = segments_from_whisper(raw, base)
        if job.system and job.system.exists() and not is_silent(job.system):
            raw = transcribe_track(job.system, job.directory / "system.asr")
            system_segs = segments_from_whisper(raw, "Them")

        status.write("diarizing", 0.6)
        segments, speakers, diarized = attribute_speakers(job, mic_segs, system_segs)

        vocab = merge_vocab(load_vocab(job.directory), load_user_vocab())
        biased = bool(vocab)
        terms = [t.get("canonical", "") for t in vocab if isinstance(t, dict)]
        terms = [t for t in terms if t]
        for seg in segments:
            seg.text, _ = correct(seg.text, vocab)

        status.write("packaging", 0.9)
        rev = model_revision()
        (job.directory / "transcript.json").write_text(
            json.dumps(
                to_json(
                    job.meeting_id, job.profile, "he", segments, speakers, diarized,
                    engine=ENGINE, model_revision=rev, biased=biased,
                ),
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        (job.directory / "transcript.txt").write_text(to_text(segments), encoding="utf-8")
        (job.directory / "metadata.json").write_text(
            json.dumps(
                build_metadata(
                    job,
                    engine=ENGINE,
                    model_revision=rev,
                    language="he",
                    biased=biased,
                    vocabulary_terms_used=terms,
                    context=ctx,
                ),
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        status.outputs["transcript"] = "transcript.json"
        status.outputs["transcript_txt"] = "transcript.txt"
        status.outputs["metadata"] = "metadata.json"

        # Diarization is MVP-accepted but unverified on a real multi-party *call* (DECISIONS 4c).
        # Log a per-meeting summary so live calls leave a reviewable trail to judge it on later.
        talk_s: dict[str, int] = {}
        for s in segments:
            talk_s[s.speaker] = talk_s.get(s.speaker, 0) + (s.end_ms - s.start_ms) // 1000
        print(
            f"diarization profile={job.profile} diarized={diarized} speakers={len(speakers)} "
            f"talk_s={json.dumps(talk_s, ensure_ascii=False)}",
            file=sys.stderr,
        )

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
