"""Whole-token post-correction (ADR-004 / P1)."""

from __future__ import annotations

from in_meetings_pipeline.postcorrect import correct

VOCAB = [
    {"canonical": "IN Venture", "variants": ["נדוויינצ'ר", "עם Venture"]},
    {"canonical": "General Motors", "variants": ["GM"]},
]


def test_replaces_whole_token_variant() -> None:
    text, counts = correct("אז אנחנו נדוויינצ'ר עובדים", VOCAB)
    assert "IN Venture" in text
    assert counts["IN Venture"] == 1


def test_replaces_multiword_variant() -> None:
    text, _ = correct("עבדנו עם Venture שנה", VOCAB)
    assert "IN Venture" in text and "עם Venture" not in text


def test_does_not_replace_inside_larger_token() -> None:
    # "GMC" must NOT become "General MotorsC"; the bare word "GM" must.
    text, counts = correct("רכב GMC חדש מול GM", VOCAB)
    assert "GMC" in text
    assert "General Motors" in text
    assert counts["General Motors"] == 1


def test_no_vocab_is_noop() -> None:
    assert correct("שום דבר", []) == ("שום דבר", {})
