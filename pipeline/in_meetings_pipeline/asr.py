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


def resolve_vad_model() -> Path | None:
    """The Silero VAD model for whisper.cpp, if available.

    When present, ASR runs with `--vad` so whisper only transcribes detected speech — it won't hallucinate
    text on *within-track* silence (the gaps when the remote side isn't talking). Absent → no VAD; whole-track
    silence is still caught by `is_silent`. Overridable via IN_MEETINGS_VAD_MODEL (the app points it at the
    ModelManager-provisioned copy); dev default is the benchmark copy.
    """
    if env := os.environ.get("IN_MEETINGS_VAD_MODEL"):
        p = Path(env)
        return p if p.exists() else None
    default = Path(__file__).resolve().parent.parent / "benchmarks" / "models" / "ggml-silero-v5.1.2.bin"
    return default if default.exists() else None


def whisper_cmd(model: Path, wav: Path, out_base: Path, language: str, vad_model: Path | None) -> list[str]:
    """Build the whisper.cpp invocation (pure, unit-tested). VAD is added only when a model is available."""
    cmd = [WHISPER_CLI, "-m", str(model), "-f", str(wav), "-l", language,
           "-bs", "5", "-oj", "-of", str(out_base)]
    if vad_model is not None:
        cmd += ["--vad", "--vad-model", str(vad_model)]
    return cmd


def transcribe_track(wav: Path, out_base: Path, language: str = "he", model: Path | None = None) -> list[dict]:
    """Transcribe one WAV; returns whisper.cpp's raw segments [{offsets:{from,to}, text}, ...].

    Writes `<out_base>.json` (the raw ASR output, kept for debugging). Runs Silero VAD when the model is
    available (`resolve_vad_model`) so silence within the track isn't hallucinated into text.
    """
    model = model or resolve_model()
    if not model.exists():
        raise FileNotFoundError(f"ASR model not found: {model}")
    cmd = whisper_cmd(model, wav, out_base, language, resolve_vad_model())
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
