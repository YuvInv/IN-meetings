"""metadata.json is the frozen ADR-005 sidecar (schema/metadata.schema.json)."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import soundfile as sf

from in_meetings_pipeline.job import Job
from in_meetings_pipeline.metadata import SCHEMA_VERSION, build_metadata


def _wav(path: Path, seconds: float = 1.0, rate: int = 16000) -> Path:
    sf.write(str(path), np.zeros(int(seconds * rate), dtype="float32"), rate)
    return path


def test_build_metadata_call_profile(tmp_path: Path) -> None:
    mic = _wav(tmp_path / "mic.wav", 2.0)
    system = _wav(tmp_path / "system.wav", 2.0)
    job = Job(
        "2026-06-14-1000", tmp_path, "call", mic, system,
        capture_source_app="us.zoom.xos", video=False,
    )

    md = build_metadata(
        job, engine="whisper.cpp", model_revision="ivrit-large-v3-turbo",
        language="he", biased=False,
    )

    assert md["schema_version"] == SCHEMA_VERSION
    assert md["meeting"]["type"] == "call"
    assert md["meeting"]["start"] and md["meeting"]["end"]
    assert set(md["recording"]["tracks"]) == {"mic", "system"}
    assert md["recording"]["durations"]["mic"] == 2.0
    assert md["recording"]["sample_rate"] == 16000
    assert md["recording"]["capture_source_app"] == "us.zoom.xos"
    assert md["transcription"]["engine"] == "whisper.cpp"
    assert md["company"]["matched"] is False
    assert md["context"]["sources"]["calendar"] == "empty"


def test_build_metadata_in_person_has_no_system_track(tmp_path: Path) -> None:
    mic = _wav(tmp_path / "mic.wav", 1.0)
    job = Job("2026-06-14-1100", tmp_path, "inPerson", mic, None)

    md = build_metadata(
        job, engine="whisper.cpp", model_revision="rev", language="he", biased=False,
    )

    assert md["meeting"]["type"] == "in_person"
    assert md["recording"]["tracks"] == ["mic"]
    assert md["recording"]["capture_source_app"] is None
