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


def is_silent(wav: Path, rms_threshold: float = 1e-3) -> bool:
    """True when a track carries no meaningful audio energy.

    Guards ASR against whisper.cpp hallucinating Hebrew text on silence: the remote ("system") track of
    a solo call is digital zero, and the ivrit model invents Knesset boilerplate on it (observed
    2026-06-14, attributed to "Them"). RMS, not peak, so a stray click doesn't defeat the gate; the
    threshold sits far below real speech (even a fraction of a second of speech in a long track clears it).
    """
    try:
        import numpy as np
        import soundfile as sf

        data, _ = sf.read(str(wav))
        if getattr(data, "ndim", 1) > 1:
            data = data.mean(axis=1)
        if len(data) == 0:
            return True
        return float(np.sqrt(np.mean(np.square(data)))) < rms_threshold
    except Exception:  # noqa: BLE001 — if we can't measure it, don't suppress; fall through to ASR
        return False
