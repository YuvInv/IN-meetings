"""Contract tests: the frozen schemas, the golden fixture, and the pipeline's emitted output all agree.

The golden fixture (schema/fixtures/golden-package/) is the single anchor both sides test against —
mirrored into ~/repos/claude-skills for the --package adapter (ADR-005).
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf
from jsonschema import Draft202012Validator

import in_meetings_pipeline.__main__ as pipeline

SCHEMA = Path(__file__).resolve().parents[2] / "schema"
FIXTURE = SCHEMA / "fixtures" / "golden-package"


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


@pytest.mark.parametrize("name", ["transcript.schema.json", "metadata.schema.json"])
def test_schema_is_valid_draft202012(name: str) -> None:
    Draft202012Validator.check_schema(_load(SCHEMA / name))


def test_golden_transcript_matches_schema() -> None:
    Draft202012Validator(_load(SCHEMA / "transcript.schema.json")).validate(
        _load(FIXTURE / "transcript.json")
    )


def test_golden_metadata_matches_schema() -> None:
    Draft202012Validator(_load(SCHEMA / "metadata.schema.json")).validate(
        _load(FIXTURE / "metadata.json")
    )


def test_emitted_package_validates(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """run() must emit schema-valid transcript.json + metadata.json — proves the writers, not the fixture."""
    for name in ("mic.wav", "system.wav"):
        sf.write(str(tmp_path / name), np.zeros(16000, dtype="float32"), 16000)

    # Stub the heavy bits (whisper-cli + senko) so the assembly path runs without them.
    monkeypatch.setattr(
        pipeline, "transcribe_track",
        lambda wav, out_base, **kw: [{"offsets": {"from": 0, "to": 1000}, "text": "שלום"}],
    )
    monkeypatch.setattr(pipeline, "_safe_turns", lambda wav: [])  # no diarization → graceful
    monkeypatch.setattr(pipeline, "model_revision", lambda: "ivrit-large-v3-turbo")

    job = {
        "meeting_id": "2026-06-14-1000",
        "directory": str(tmp_path),
        "profile": "call",
        "tracks": {"mic": "mic.wav", "system": "system.wav"},
        "capture_source_app": "us.zoom.xos",
    }
    (tmp_path / "job.json").write_text(json.dumps(job), encoding="utf-8")

    assert pipeline.run(tmp_path / "job.json") == 0

    Draft202012Validator(_load(SCHEMA / "transcript.schema.json")).validate(
        _load(tmp_path / "transcript.json")
    )
    Draft202012Validator(_load(SCHEMA / "metadata.schema.json")).validate(
        _load(tmp_path / "metadata.json")
    )
