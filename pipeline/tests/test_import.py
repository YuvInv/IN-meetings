"""The 'import an audio file assigned to a calendar event' contract: a single mixed track is processed as
profile 'inPerson', and a context.input.json pinned to exactly one event fills metadata with that event's
id + attendees. The extra job-level 'source' key must be ignored by Job.load."""
import json
from pathlib import Path

from in_meetings_pipeline.__main__ import run
from in_meetings_pipeline.job import Job


def test_import_job_tolerates_source_key(tmp_path: Path) -> None:
    job_json = {
        "meeting_id": "imp-1", "directory": str(tmp_path), "profile": "inPerson",
        "tracks": {"mic": "audio.wav"}, "started_at": "2026-06-22T10:00:00Z",
        "ended_at": "2026-06-22T10:30:00Z", "video": False, "source": "imported",
    }
    p = tmp_path / "job.json"
    p.write_text(json.dumps(job_json), encoding="utf-8")
    job = Job.load(p)                      # must not raise on the unknown 'source' key
    assert job.profile == "inPerson"
    assert job.mic == tmp_path / "audio.wav"
    assert job.system is None


def test_pinned_single_candidate_fills_metadata(tmp_path: Path) -> None:
    # context.input.json pinned to ONE candidate whose window == the meeting window (100% overlap match).
    (tmp_path / "context.input.json").write_text(json.dumps({
        "status": "ok", "internal_domain": "in-venture.com",
        "hints": {"capture_source_app": "", "started_at": "2026-06-22T10:00:00Z",
                  "ended_at": "2026-06-22T10:30:00Z"},
        "candidates": [{
            "id": "evt123", "summary": "Acme intro",
            "start": "2026-06-22T10:00:00Z", "end": "2026-06-22T10:30:00Z", "has_link": True,
            "attendees": [{"email": "dana@acme.com", "displayName": "Dana Cohen", "organizer": False}],
        }],
    }), encoding="utf-8")
    # Empty tracks → run() assembles context + writes metadata with no audio (no whisper/senko), exactly
    # like test_context.py::test_run_invokes_assembler_and_packages. profile inPerson + the import source key.
    job = {"meeting_id": "imp-1", "directory": str(tmp_path), "profile": "inPerson",
           "tracks": {}, "started_at": "2026-06-22T10:00:00Z", "ended_at": "2026-06-22T10:30:00Z",
           "source": "imported"}
    (tmp_path / "job.json").write_text(json.dumps(job), encoding="utf-8")

    assert run(tmp_path / "job.json") == 0
    md = json.loads((tmp_path / "metadata.json").read_text(encoding="utf-8"))
    assert md["meeting"]["calendar_event_id"] == "evt123"
    assert md["meeting"]["type"] == "in_person"
    assert any(a["email"] == "dana@acme.com" for a in md.get("attendees", []))
