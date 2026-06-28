"""User-taught vocabulary corrections (dashboard find-&-replace "remember this") applied to every meeting."""

from __future__ import annotations

import json

from in_meetings_pipeline.__main__ import load_user_vocab, merge_vocab
from in_meetings_pipeline.postcorrect import correct


def test_load_user_vocab_reads_env_path(tmp_path, monkeypatch):
    p = tmp_path / "vocab.json"
    p.write_text(json.dumps([{"canonical": "Anthropic", "variants": ["אנתרופיק"]}]), encoding="utf-8")
    monkeypatch.setenv("IN_MEETINGS_VOCAB_CORRECTIONS", str(p))
    assert load_user_vocab() == [{"canonical": "Anthropic", "variants": ["אנתרופיק"]}]


def test_load_user_vocab_absent_returns_empty(tmp_path, monkeypatch):
    monkeypatch.setenv("IN_MEETINGS_VOCAB_CORRECTIONS", str(tmp_path / "nope.json"))
    assert load_user_vocab() == []


def test_load_user_vocab_malformed_returns_empty(tmp_path, monkeypatch):
    p = tmp_path / "vocab.json"
    p.write_text("not json", encoding="utf-8")
    monkeypatch.setenv("IN_MEETINGS_VOCAB_CORRECTIONS", str(p))
    assert load_user_vocab() == []


def test_merge_vocab_unions_variants_by_canonical():
    base = [{"canonical": "Anthropic", "variants": ["antropic"]}]
    extra = [
        {"canonical": "Anthropic", "variants": ["אנתרופיק", "antropic"]},
        {"canonical": "Haiku", "variants": ["הייקו"]},
    ]
    merged = merge_vocab(base, extra)
    anthropic = next(e for e in merged if e["canonical"] == "Anthropic")
    assert anthropic["variants"] == ["antropic", "אנתרופיק"]  # base first, deduped
    assert any(e["canonical"] == "Haiku" for e in merged)


def test_user_vocab_applies_via_correct(tmp_path, monkeypatch):
    p = tmp_path / "vocab.json"
    p.write_text(json.dumps([{"canonical": "Anthropic", "variants": ["אנתרופיק"]}]), encoding="utf-8")
    monkeypatch.setenv("IN_MEETINGS_VOCAB_CORRECTIONS", str(p))
    vocab = merge_vocab([], load_user_vocab())
    out, counts = correct("אנתרופיק מצוין", vocab)
    assert out == "Anthropic מצוין"
    assert counts.get("Anthropic") == 1
