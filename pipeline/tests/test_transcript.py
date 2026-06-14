"""transcript.json shape is the frozen ADR-005 contract (schema/transcript.schema.json)."""

from __future__ import annotations

from in_meetings_pipeline.transcript import Segment, to_json, to_text


def test_to_json_emits_utterances_in_seconds() -> None:
    segs = [Segment(0, 3200, "Me", "שלום"), Segment(3200, 5000, "Them", "מה נשמע")]
    speakers = [
        {"id": "Me", "side": "internal", "track": "mic"},
        {"id": "Them", "side": "external", "track": "system"},
    ]
    out = to_json(
        "2026-06-14-1000", "call", "he", segs, speakers, True,
        engine="whisper.cpp", model_revision="ivrit-large-v3-turbo", biased=False,
    )

    assert out["engine"] == "whisper.cpp"
    assert out["model_revision"] == "ivrit-large-v3-turbo"
    assert out["biased"] is False
    assert out["diarized"] is True
    # ADR-005 names the array "utterances"; the old "segments" key is gone.
    assert "utterances" in out and "segments" not in out

    u0 = out["utterances"][0]
    assert u0 == {"text": "שלום", "start": 0.0, "end": 3.2, "speaker_id": "Me", "confidence": None}

    # every speaker_id references a row in the speakers table
    ids = {s["id"] for s in out["speakers"]}
    assert all(u["speaker_id"] in ids for u in out["utterances"])


def test_to_text_is_unchanged() -> None:
    assert to_text([Segment(0, 1000, "Me", "שלום")]) == "[00:00] Me: שלום\n"
