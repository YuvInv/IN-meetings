"""Assemble metadata.json — the ADR-005 sidecar — from record-time facts + transcription facts.

The pipeline is the single writer of the context package (ADR-009): Swift hands record-time facts
via job.json, Python merges them with the transcription/diarization results here. The Phase-2 context
assembler (context_assembler.py) supplies calendar-derived fields via `context`; absent it, the
calendar/CRM/consent fields stay null/empty (forward-compatible — schema/metadata.schema.json).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

from .context_assembler import AssembledContext
from .job import Job

SCHEMA_VERSION = "1.0"

_PROFILE_TO_TYPE = {"call": "call", "inPerson": "in_person"}


def _wav_info(path: Path | None) -> tuple[float | None, int | None]:
    """(duration_seconds, sample_rate) for a WAV, or (None, None).

    Uses soundfile so it reads the float32 capture tracks the stdlib `wave` module rejects.
    """
    if not path or not path.exists():
        return None, None
    try:
        import soundfile as sf

        info = sf.info(str(path))
        return round(info.duration, 3), int(info.samplerate)
    except Exception:  # noqa: BLE001 — missing/unreadable audio must not fail packaging
        return None, None


def _meeting_times(job: Job, mic_duration: float | None) -> tuple[str, str]:
    """ISO-8601 (start, end). Prefer the recorder's wall-clock; else derive from the mic file mtime."""
    if job.started_at and job.ended_at:
        return job.started_at, job.ended_at
    end_dt: datetime | None = None
    if job.mic and job.mic.exists():
        end_dt = datetime.fromtimestamp(job.mic.stat().st_mtime, tz=timezone.utc)
    if end_dt is None:
        end_dt = datetime.now(timezone.utc)
    start_dt = end_dt - timedelta(seconds=mic_duration or 0.0)
    return job.started_at or start_dt.isoformat(), job.ended_at or end_dt.isoformat()


def build_metadata(
    job: Job,
    *,
    engine: str,
    model_revision: str,
    language: str,
    biased: bool,
    vocabulary_terms_used: list[str] | None = None,
    context: AssembledContext | None = None,
) -> dict:
    """Build the metadata.json dict for a finished recording (validates against metadata.schema.json)."""
    durations: dict[str, float] = {}
    tracks: list[str] = []
    rates: dict[str, int] = {}
    for name, path in (("mic", job.mic), ("system", job.system)):
        dur, rate = _wav_info(path)
        if dur is not None:
            durations[name] = dur
            tracks.append(name)
            if rate is not None:
                rates[name] = rate

    start, end = _meeting_times(job, durations.get("mic"))
    sample_rate = job.sample_rate or rates.get("mic") or rates.get("system")

    cal_status = context.calendar_status if context else "empty"
    attendees = (
        [{"name": a.name, "email": a.email, "side": a.side, "matched_crm_contact_id": None}
         for a in context.attendees]
        if context else []
    )
    company = (
        context.company if (context and context.company)
        else {"name": None, "sevanta_deal_id": None, "dealigence_id": None,
              "matched": False, "source": None}
    )

    return {
        "schema_version": SCHEMA_VERSION,
        "meeting": {
            "title": context.title if context else None,
            "start": start,
            "end": end,
            "type": _PROFILE_TO_TYPE.get(job.profile, "call"),
            "calendar_event_id": context.calendar_event_id if context else None,
        },
        "attendees": attendees,
        "company": company,
        "recording": {
            "durations": durations,
            "tracks": tracks,
            "sample_rate": sample_rate,
            "capture_source_app": job.capture_source_app,
            "video": bool(job.video),
        },
        "transcription": {
            "engine": engine,
            "model_revision": model_revision,
            "language": language,
            "biased": biased,
            "vocabulary_terms_used": vocabulary_terms_used or [],
        },
        "context": {
            "sources": {"calendar": cal_status, "saventa": "empty", "dealigence": "empty"},
        },
        "consent": {"status": "none", "jurisdiction_hint": None},
    }
