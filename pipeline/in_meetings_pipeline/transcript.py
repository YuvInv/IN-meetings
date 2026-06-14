"""Build the merged transcript from per-track ASR output.

Call-time shortcut (ADR-002): the mic track is "Me", the system track is "Them". Multi-speaker
diarization *within* a track (several remote participants, or an in-person room) is slice 4c.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class Segment:
    start_ms: int
    end_ms: int
    speaker: str
    text: str


def segments_from_whisper(raw: list[dict], speaker: str) -> list[Segment]:
    out: list[Segment] = []
    for s in raw:
        text = (s.get("text") or "").strip()
        if not text:
            continue
        off = s.get("offsets", {})
        out.append(Segment(int(off.get("from", 0)), int(off.get("to", 0)), speaker, text))
    return out


def merge(*tracks: list[Segment]) -> list[Segment]:
    merged = [s for track in tracks for s in track]
    merged.sort(key=lambda s: s.start_ms)
    return merged


def to_json(
    meeting_id: str,
    profile: str,
    language: str,
    segments: list[Segment],
    speakers: list[dict] | None = None,
    diarized: bool = False,
    *,
    engine: str = "",
    model_revision: str = "",
    biased: bool = False,
) -> dict:
    """Serialize to the frozen ADR-005 transcript.json shape (schema/transcript.schema.json).

    Times are seconds; each utterance's speaker_id references speakers[].id. meeting_id / profile /
    diarized are additive fields (consumers ignore unknowns).
    """
    return {
        "meeting_id": meeting_id,
        "profile": profile,
        "language": language,
        "engine": engine,
        "model_revision": model_revision,
        "biased": biased,
        "diarized": diarized,
        "speakers": speakers or [],
        "utterances": [
            {
                "text": s.text,
                "start": round(s.start_ms / 1000, 3),
                "end": round(s.end_ms / 1000, 3),
                "speaker_id": s.speaker,
                "confidence": None,
            }
            for s in segments
        ],
    }


def to_text(segments: list[Segment]) -> str:
    lines = []
    for s in segments:
        mm, ss = divmod(s.start_ms // 1000, 60)
        lines.append(f"[{mm:02d}:{ss:02d}] {s.speaker}: {s.text}")
    return "\n".join(lines) + ("\n" if lines else "")
