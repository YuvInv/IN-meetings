"""Slice 4c: assigning ASR segments to diarized speakers, and stable speaker labels.

The senko call itself is verified live on real audio (it needs CoreML models + a WAV); these
tests pin the pure logic that turns diarization turns + ASR segments into a speaker-attributed
transcript.
"""

from __future__ import annotations

from in_meetings_pipeline.diarize import (
    SpeakerTurn,
    assign_speakers,
    label_track,
    order_labels,
)
from in_meetings_pipeline.transcript import Segment


def seg(start_ms: int, end_ms: int, *, text: str = "x", speaker: str = "Them") -> Segment:
    return Segment(start_ms, end_ms, speaker, text)


def turn(start_ms: int, end_ms: int, speaker: str) -> SpeakerTurn:
    return SpeakerTurn(start_ms, end_ms, speaker)


def test_segment_inside_turn_gets_that_speaker():
    out = assign_speakers([seg(1000, 2000)], [turn(0, 5000, "SPEAKER_01")])
    assert out[0].speaker == "SPEAKER_01"
    assert out[0].text == "x"  # text + timing preserved
    assert (out[0].start_ms, out[0].end_ms) == (1000, 2000)


def test_segment_spanning_two_turns_takes_majority_overlap():
    # 1000–2000 overlaps A by 200ms (1000–1200) and B by 800ms (1200–2000) → B wins
    out = assign_speakers([seg(1000, 2000)], [turn(0, 1200, "A"), turn(1200, 3000, "B")])
    assert out[0].speaker == "B"


def test_segment_with_no_overlap_takes_nearest_turn():
    # midpoint 5500: gap to A (ends 1000) = 4500; gap to B (starts 8000) = 2500 → B
    out = assign_speakers([seg(5000, 6000)], [turn(0, 1000, "A"), turn(8000, 9000, "B")])
    assert out[0].speaker == "B"


def test_no_turns_leaves_segments_unchanged():
    out = assign_speakers([seg(1000, 2000, speaker="Them")], [])
    assert out[0].speaker == "Them"


def test_order_labels_numbers_speakers_by_first_appearance():
    turns = [turn(2000, 3000, "SPEAKER_07"), turn(500, 1000, "SPEAKER_03"), turn(4000, 5000, "SPEAKER_07")]
    # earliest start belongs to SPEAKER_03 (500) → Speaker 1; SPEAKER_07 (2000) → Speaker 2
    assert order_labels(turns) == {"SPEAKER_03": "Speaker 1", "SPEAKER_07": "Speaker 2"}


def test_label_track_assigns_speaker_numbers_and_builds_table():
    segs = [seg(0, 1000), seg(1000, 2000)]
    turns = [turn(0, 1000, "SPEAKER_05"), turn(1000, 2000, "SPEAKER_09")]
    labeled, speakers = label_track(segs, turns, side="unknown", track="mic")
    assert [s.speaker for s in labeled] == ["Speaker 1", "Speaker 2"]
    assert speakers == [
        {"id": "Speaker 1", "side": "unknown", "track": "mic"},
        {"id": "Speaker 2", "side": "unknown", "track": "mic"},
    ]


def test_label_track_single_speaker_uses_solo_label():
    # a 1:1 call's remote (system) track collapses to the friendly "Them" rather than "Speaker 1"
    labeled, speakers = label_track(
        [seg(0, 2000)], [turn(0, 2000, "SPEAKER_00")], side="external", track="system", solo_label="Them"
    )
    assert labeled[0].speaker == "Them"
    assert speakers == [{"id": "Them", "side": "external", "track": "system"}]


def test_label_track_no_turns_keeps_segments_and_emits_no_speakers():
    labeled, speakers = label_track(
        [seg(0, 1000, speaker="Speaker 1")], [], side="unknown", track="mic"
    )
    assert [s.speaker for s in labeled] == ["Speaker 1"]
    assert speakers == []
