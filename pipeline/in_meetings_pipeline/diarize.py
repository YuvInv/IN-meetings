"""Speaker diarization (slice 4c).

senko (CoreML/ANE on Mac) splits a single audio track into speaker turns; we then attribute each
ASR segment to the speaker who was talking during it (max temporal overlap). See ADR-003/ADR-011:
- call (dual-track) → diarize the *system* track (the remote side); the mic is the known IN partner.
- in-person (mic-only) → diarize the *mic* track (everyone is on it).

The senko call is verified live on real audio (`diarize_track`); the attribution + labeling logic is
unit-tested (`assign_speakers`, `order_labels`).
"""

from __future__ import annotations

import tempfile
from dataclasses import dataclass, replace
from pathlib import Path

from .transcript import Segment


@dataclass
class SpeakerTurn:
    start_ms: int
    end_ms: int
    speaker: str  # raw diarizer id, e.g. "SPEAKER_01"


def _overlap_ms(seg: Segment, turn: SpeakerTurn) -> int:
    return max(0, min(seg.end_ms, turn.end_ms) - max(seg.start_ms, turn.start_ms))


def _distance_ms(seg: Segment, turn: SpeakerTurn) -> int:
    """Gap between a segment and a turn (0 if they overlap)."""
    return max(0, seg.start_ms - turn.end_ms, turn.start_ms - seg.end_ms)


def assign_speakers(segments: list[Segment], turns: list[SpeakerTurn]) -> list[Segment]:
    """Relabel each segment with the diarized speaker who most overlaps it.

    No overlap → nearest turn in time. No turns at all → segments unchanged.
    """
    if not turns:
        return list(segments)

    out: list[Segment] = []
    for seg in segments:
        by_speaker: dict[str, int] = {}
        for t in turns:
            ov = _overlap_ms(seg, t)
            if ov:
                by_speaker[t.speaker] = by_speaker.get(t.speaker, 0) + ov
        if by_speaker:
            speaker = max(by_speaker, key=lambda s: by_speaker[s])
        else:
            nearest = min(turns, key=lambda t: (_distance_ms(seg, t), t.start_ms))
            speaker = nearest.speaker
        out.append(replace(seg, speaker=speaker))
    return out


def order_labels(turns: list[SpeakerTurn]) -> dict[str, str]:
    """Map raw diarizer ids → "Speaker 1", "Speaker 2", … ordered by first appearance."""
    first_seen: dict[str, int] = {}
    for t in turns:
        if t.speaker not in first_seen or t.start_ms < first_seen[t.speaker]:
            first_seen[t.speaker] = t.start_ms
    ordered = sorted(first_seen, key=lambda s: (first_seen[s], s))
    return {raw: f"Speaker {i}" for i, raw in enumerate(ordered, start=1)}


def label_track(
    segments: list[Segment],
    turns: list[SpeakerTurn],
    *,
    side: str,
    track: str,
    solo_label: str | None = None,
) -> tuple[list[Segment], list[dict]]:
    """Attribute `segments` to diarized speakers and produce the speakers table for this track.

    `side` is "internal" | "external" | "unknown" (ADR-003). `solo_label` lets a single-speaker
    track keep a friendlier name (a 1:1 call's remote side stays "Them", not "Speaker 1").
    Returns (relabeled_segments, speakers) where each speaker is {id, side, track}; with no turns
    the segments pass through unchanged and the table is empty (graceful degradation).
    """
    if not turns:
        return list(segments), []

    labels = order_labels(turns)
    if solo_label and len(labels) == 1:
        labels = {raw: solo_label for raw in labels}

    assigned = assign_speakers(segments, turns)
    relabeled = [replace(s, speaker=labels[s.speaker]) for s in assigned]
    speakers = [{"id": labels[raw], "side": side, "track": track} for raw in labels]
    return relabeled, speakers


def diarize_track(wav: Path, *, quiet: bool = True) -> list[SpeakerTurn]:
    """Run senko on one audio track and return its speaker turns (ms).

    senko wants 16 kHz mono 16-bit input; capture tracks may be 48 kHz float, so normalize first
    (pure Python via soundfile + scipy — no ffmpeg/PATH dependency in the spawned pipeline).
    """
    import senko  # lazy: keep the pure logic importable without the CoreML stack

    norm = _to_16k_mono_s16(Path(wav))
    try:
        diarizer = senko.Diarizer(device="auto", warmup=False, quiet=quiet)
        result = diarizer.diarize(str(norm), generate_colors=False)
    finally:
        norm.unlink(missing_ok=True)
    return [
        SpeakerTurn(int(s["start"] * 1000), int(s["end"] * 1000), str(s["speaker"]))
        for s in result["merged_segments"]
    ]


def _to_16k_mono_s16(wav: Path) -> Path:
    """Downmix to mono, resample to 16 kHz, write a temp 16-bit PCM WAV; returns its path."""
    import math
    import os

    import soundfile as sf
    from scipy.signal import resample_poly

    data, sr = sf.read(str(wav), dtype="float32", always_2d=True)
    mono = data.mean(axis=1)
    if sr != 16000:
        g = math.gcd(int(sr), 16000)
        mono = resample_poly(mono, 16000 // g, int(sr) // g)
    fd, path = tempfile.mkstemp(suffix=".16k.wav")
    os.close(fd)  # soundfile rewrites the empty file mkstemp created
    sf.write(path, mono, 16000, subtype="PCM_16")
    return Path(path)
