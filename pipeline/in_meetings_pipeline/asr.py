"""Hebrew ASR via whisper.cpp (ivrit-ai turbo GGML) — the verified P1 benchmark invocation.

`whisper-cli` is expected on PATH (the Swift app sets it; see JobBridge). The model defaults to the
benchmark copy and is overridable via IN_MEETINGS_MODEL (Phase 5 bundles it in the app).
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

WHISPER_CLI = os.environ.get("IN_MEETINGS_WHISPER", "whisper-cli")
ENGINE = "whisper.cpp"


def resolve_model() -> Path:
    if env := os.environ.get("IN_MEETINGS_MODEL"):
        return Path(env)
    return Path(__file__).resolve().parent.parent / "benchmarks" / "models" / "ivrit-large-v3-turbo.ggml.bin"


def model_revision(model: Path | None = None) -> str:
    """A clean identifier for the active model, e.g. "ivrit-large-v3-turbo" (drops .ggml.bin)."""
    return (model or resolve_model()).name.split(".")[0]


def transcribe_track(wav: Path, out_base: Path, language: str = "he", model: Path | None = None) -> list[dict]:
    """Transcribe one WAV; returns whisper.cpp's raw segments [{offsets:{from,to}, text}, ...].

    Writes `<out_base>.json` (the raw ASR output, kept for debugging).
    """
    model = model or resolve_model()
    if not model.exists():
        raise FileNotFoundError(f"ASR model not found: {model}")
    cmd = [WHISPER_CLI, "-m", str(model), "-f", str(wav), "-l", language,
           "-bs", "5", "-oj", "-of", str(out_base)]
    subprocess.run(cmd, check=True, capture_output=True)
    raw = json.loads(Path(f"{out_base}.json").read_text(encoding="utf-8"))
    return raw.get("transcription", [])
