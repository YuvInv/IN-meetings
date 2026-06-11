"""Slice-4c diarization bake-off: senko vs pyannote on real Hebrew meeting audio.

Decides ADR-003's "senko primary" by data instead of assumption (senko's embedding
model is English+Mandarin; Hebrew DER is unvalidated). Run each engine on the same
clip and compare speaker count, segmentation, per-speaker talk time, and wall-clock.

    python diarize_bakeoff.py senko    <wav> [out.json]
    python diarize_bakeoff.py pyannote <wav> [out.json]   # needs HF_TOKEN + model terms
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path


def _norm(segments: list[dict]) -> list[dict]:
    """Normalize an engine's segments to {start, end, speaker} (seconds, str)."""
    out = []
    for s in segments:
        start = s.get("start", s.get("start_time"))
        end = s.get("end", s.get("end_time"))
        spk = s.get("speaker", s.get("spkid", s.get("label", s.get("speaker_id"))))
        out.append({"start": float(start), "end": float(end), "speaker": str(spk)})
    return out


def _summary(segments: list[dict]) -> dict:
    speakers: dict[str, float] = {}
    for s in segments:
        speakers[s["speaker"]] = speakers.get(s["speaker"], 0.0) + (s["end"] - s["start"])
    speech = sum(speakers.values())
    return {
        "n_segments": len(segments),
        "n_speakers": len(speakers),
        "speech_seconds": round(speech, 1),
        "per_speaker_seconds": {k: round(v, 1) for k, v in sorted(speakers.items())},
    }


def run_senko(wav: str) -> tuple[list[dict], float]:
    import senko

    d = senko.Diarizer(device="auto", warmup=True, quiet=False)
    t0 = time.time()
    result = d.diarize(wav, generate_colors=False)
    elapsed = time.time() - t0
    segs = result["merged_segments"]
    print(f"[senko] raw first segment: {segs[0]!r}", file=sys.stderr)
    return _norm(segs), elapsed


def run_pyannote(wav: str) -> tuple[list[dict], float]:
    import os

    from pyannote.audio import Pipeline

    token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    pipe = Pipeline.from_pretrained("pyannote/speaker-diarization-community-1", use_auth_token=token)
    try:
        import torch

        if torch.backends.mps.is_available():
            pipe.to(torch.device("mps"))
    except Exception as exc:  # noqa: BLE001
        print(f"[pyannote] MPS unavailable ({exc}); using CPU", file=sys.stderr)
    t0 = time.time()
    diar = pipe(wav)
    elapsed = time.time() - t0
    segs = [
        {"start": turn.start, "end": turn.end, "speaker": label}
        for turn, _, label in diar.itertracks(yield_label=True)
    ]
    return _norm(segs), elapsed


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    engine, wav = argv[1], argv[2]
    out = Path(argv[3]) if len(argv) > 3 else Path(f"results/diar_{engine}.json")
    runner = {"senko": run_senko, "pyannote": run_pyannote}[engine]

    audio_dur = None
    try:
        import soundfile as sf

        info = sf.info(wav)
        audio_dur = info.frames / info.samplerate
    except Exception:  # noqa: BLE001
        pass

    segments, elapsed = runner(wav)
    summary = _summary(segments)
    rtf = round(elapsed / audio_dur, 4) if audio_dur else None
    report = {
        "engine": engine,
        "wav": wav,
        "audio_seconds": round(audio_dur, 1) if audio_dur else None,
        "wall_seconds": round(elapsed, 2),
        "rtf": rtf,
        **summary,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"report": report, "segments": segments}, ensure_ascii=False, indent=2))

    print("\n=== DIARIZATION BAKE-OFF ===")
    for k, v in report.items():
        print(f"  {k}: {v}")
    print(f"  saved: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
