"""ASR silence-gating — whisper.cpp hallucinates Hebrew on silent tracks.

Observed 2026-06-14: a solo Google Meet produced an all-zero remote ("system") track, and the ivrit
model invented "אדוני היושב-ראש, חבריי חברי הכנסת" (Knesset boilerplate), attributed to "Them".
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import soundfile as sf

from in_meetings_pipeline.__main__ import run
from in_meetings_pipeline.asr import is_silent


def _wav(path: Path, data, rate: int = 16000) -> Path:
    sf.write(str(path), np.asarray(data, dtype="float32"), rate)
    return path


def test_is_silent_on_digital_zero(tmp_path: Path) -> None:
    assert is_silent(_wav(tmp_path / "z.wav", np.zeros(16000))) is True


def test_is_silent_on_empty_file(tmp_path: Path) -> None:
    assert is_silent(_wav(tmp_path / "e.wav", np.zeros(0))) is True


def test_is_silent_false_on_speech_like_energy(tmp_path: Path) -> None:
    rng = np.random.default_rng(0)
    assert is_silent(_wav(tmp_path / "n.wav", rng.normal(0, 0.2, 16000))) is False


def test_run_does_not_transcribe_silent_system_track(tmp_path: Path) -> None:
    # The bug: a silent remote track was transcribed → whisper hallucinated a "Them:" line. The silent
    # track must be skipped (no whisper invoked, since it's the only track), leaving no "Them" content.
    _wav(tmp_path / "system.wav", np.zeros(48000), rate=16000)  # 3s of digital silence
    job = {"meeting_id": "2026-06-14_silent", "directory": str(tmp_path), "profile": "call",
           "tracks": {"system": "system.wav"},
           "started_at": "2026-06-14T10:00:00Z", "ended_at": "2026-06-14T10:00:03Z"}
    (tmp_path / "job.json").write_text(json.dumps(job), encoding="utf-8")

    assert run(tmp_path / "job.json") == 0
    txt = (tmp_path / "transcript.txt").read_text(encoding="utf-8")
    assert "Them" not in txt
