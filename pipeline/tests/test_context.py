"""Phase-2 context assembler (ADR-004): match -> split -> company -> vocab -> context.md -> metadata."""

from __future__ import annotations

import json
from pathlib import Path

from in_meetings_pipeline.__main__ import run
from in_meetings_pipeline.context_assembler import (
    AssembledContext,
    Attendee,
    assemble,
    build_vocab,
    hebrew_transliteration_candidates,
    load_core_lexicon,
    match_event,
    render_context_md,
    resolve_company,
    split_sides,
)

_WINDOW = ("2026-06-14T10:00:00Z", "2026-06-14T10:30:00Z")


def _evt(eid, start, end, *, link=False, attendees=None):
    return {"id": eid, "summary": "x", "start": start, "end": end,
            "has_link": link, "attendees": attendees or []}


def _write_input(directory: Path, candidates, internal_domain="in-venture.com") -> None:
    payload = {"internal_domain": internal_domain,
               "hints": {"started_at": "2026-06-14T10:00:00Z", "ended_at": "2026-06-14T10:30:00Z"},
               "candidates": candidates}
    (directory / "context.input.json").write_text(json.dumps(payload), encoding="utf-8")


# --- core lexicon ---

def test_core_lexicon_has_fund_name() -> None:
    lex = load_core_lexicon()
    canon = {e["canonical"] for e in lex}
    assert "IN Venture" in canon
    fund = next(e for e in lex if e["canonical"] == "IN Venture")
    assert "נדוויינצ'ר" in fund["variants"]


# --- match_event ---

def test_match_picks_greatest_overlap() -> None:
    cands = [
        _evt("a", "2026-06-14T09:00:00Z", "2026-06-14T10:05:00Z"),
        _evt("b", "2026-06-14T10:00:00Z", "2026-06-14T10:30:00Z"),
    ]
    assert match_event(cands, *_WINDOW)["id"] == "b"


def test_match_requires_positive_overlap() -> None:
    cands = [_evt("c", "2026-06-14T08:00:00Z", "2026-06-14T09:00:00Z")]
    assert match_event(cands, *_WINDOW) is None


def test_match_skips_all_day_events() -> None:
    cands = [_evt("allday", "2026-06-14", "2026-06-15")]
    assert match_event(cands, *_WINDOW) is None


def test_match_tiebreak_prefers_link() -> None:
    cands = [
        _evt("plain", "2026-06-14T10:00:00Z", "2026-06-14T10:30:00Z"),
        _evt("withlink", "2026-06-14T10:00:00Z", "2026-06-14T10:30:00Z", link=True),
    ]
    assert match_event(cands, *_WINDOW)["id"] == "withlink"


# --- split_sides + resolve_company ---

_EVENT = {
    "id": "e1", "summary": "Prelligence <> IN Venture",
    "attendees": [
        {"email": "yuval@in-venture.com", "displayName": "Yuval Naor", "organizer": True},
        {"email": "founder@prelligence.com", "displayName": "A Founder", "organizer": False},
        {"email": "guest@prelligence.com", "displayName": None, "organizer": False},
    ],
}


def test_split_sides_by_domain() -> None:
    att = split_sides(_EVENT, "in-venture.com")
    by_email = {a.email: a for a in att}
    assert by_email["yuval@in-venture.com"].side == "internal"
    assert by_email["founder@prelligence.com"].side == "external"
    assert by_email["guest@prelligence.com"].name == "guest"


def test_resolve_company_from_dominant_external_domain() -> None:
    att = split_sides(_EVENT, "in-venture.com")
    company = resolve_company(att, _EVENT["summary"])
    assert company["name"] == "Prelligence"
    assert company["matched"] is False
    assert company["sevanta_deal_id"] is None


def test_resolve_company_none_when_no_external() -> None:
    internal_only = {"summary": "Internal sync", "attendees": [
        {"email": "yuval@in-venture.com", "displayName": "Yuval", "organizer": True}]}
    att = split_sides(internal_only, "in-venture.com")
    assert resolve_company(att, internal_only["summary"]) is None


# --- transliteration + vocab ---

def test_transliteration_is_length_guarded() -> None:
    assert hebrew_transliteration_candidates("GM") == []
    cands = hebrew_transliteration_candidates("Prelligence")
    assert cands and all(len(c) >= 4 for c in cands)


def test_build_vocab_includes_core_and_company() -> None:
    company = {"name": "Prelligence", "matched": False}
    vocab = build_vocab(company)
    canon = {e["canonical"] for e in vocab}
    assert "IN Venture" in canon
    assert "Prelligence" in canon
    pr = next(e for e in vocab if e["canonical"] == "Prelligence")
    assert pr["variants"]


def test_build_vocab_core_only_when_no_company() -> None:
    vocab = build_vocab(None)
    assert {e["canonical"] for e in vocab} == {"IN Venture"}


# --- context.md ---

def test_context_md_has_priors_wall_and_sides() -> None:
    ctx = AssembledContext(
        title="Prelligence <> IN Venture", calendar_event_id="e1",
        attendees=[Attendee("Yuval Naor", "yuval@in-venture.com", "internal"),
                   Attendee("A Founder", "founder@prelligence.com", "external")],
        company={"name": "Prelligence", "matched": False}, calendar_status="ok")
    md = render_context_md(ctx)
    assert "PRIORS" in md and "NOT meeting content" in md
    assert "Yuval Naor" in md and "A Founder" in md
    assert "Prelligence" in md


def test_context_md_no_match_message() -> None:
    md = render_context_md(AssembledContext(calendar_status="empty"))
    assert "No calendar event matched" in md


# --- assemble orchestration ---

def test_assemble_full_match_writes_artifacts(tmp_path: Path) -> None:
    _write_input(tmp_path, [{
        "id": "e1", "summary": "Prelligence <> IN Venture",
        "start": "2026-06-14T10:00:00Z", "end": "2026-06-14T10:30:00Z", "has_link": True,
        "attendees": [{"email": "yuval@in-venture.com", "displayName": "Yuval", "organizer": True},
                      {"email": "founder@prelligence.com", "displayName": "Founder", "organizer": False}]}])
    ctx = assemble(tmp_path)
    assert ctx.calendar_status == "ok"
    assert ctx.calendar_event_id == "e1"
    assert ctx.company["name"] == "Prelligence"
    assert {a.side for a in ctx.attendees} == {"internal", "external"}
    vocab = json.loads((tmp_path / "context.vocab.json").read_text(encoding="utf-8"))
    assert "IN Venture" in {e["canonical"] for e in vocab}
    assert (tmp_path / "context.md").read_text(encoding="utf-8").startswith("# Meeting context")


def test_assemble_no_input_degrades_but_keeps_core_vocab(tmp_path: Path) -> None:
    ctx = assemble(tmp_path)  # no context.input.json
    assert ctx.calendar_status == "empty"
    assert ctx.company is None and ctx.attendees == []
    vocab = json.loads((tmp_path / "context.vocab.json").read_text(encoding="utf-8"))
    assert {e["canonical"] for e in vocab} == {"IN Venture"}


def test_assemble_no_overlap_is_empty(tmp_path: Path) -> None:
    _write_input(tmp_path, [{"id": "x", "summary": "s",
                             "start": "2026-06-14T08:00:00Z", "end": "2026-06-14T09:00:00Z",
                             "has_link": False, "attendees": []}])
    ctx = assemble(tmp_path)
    assert ctx.calendar_status == "empty"


# --- run() wiring ---

def test_run_invokes_assembler_and_packages(tmp_path: Path) -> None:
    _write_input(tmp_path, [{
        "id": "e1", "summary": "Prelligence <> IN Venture",
        "start": "2026-06-14T10:00:00Z", "end": "2026-06-14T10:30:00Z", "has_link": True,
        "attendees": [{"email": "founder@prelligence.com", "displayName": "Founder", "organizer": False}]}])
    job = {"meeting_id": "2026-06-14-1000", "directory": str(tmp_path), "profile": "call",
           "tracks": {}, "started_at": "2026-06-14T10:00:00Z", "ended_at": "2026-06-14T10:30:00Z"}
    (tmp_path / "job.json").write_text(json.dumps(job), encoding="utf-8")

    assert run(tmp_path / "job.json") == 0
    md = json.loads((tmp_path / "metadata.json").read_text(encoding="utf-8"))
    assert md["meeting"]["calendar_event_id"] == "e1"
    assert md["context"]["sources"]["calendar"] == "ok"
    assert (tmp_path / "context.md").exists()


def test_assemble_surfaces_fetch_error(tmp_path: Path) -> None:
    # A Calendar 403 (e.g. API disabled) must read as calendar:"error", not a silent "no match".
    (tmp_path / "context.input.json").write_text(
        json.dumps({"status": "error", "error": "403 Calendar API disabled"}), encoding="utf-8")
    ctx = assemble(tmp_path)
    assert ctx.calendar_status == "error"
    assert "failed" in (tmp_path / "context.md").read_text(encoding="utf-8").lower()
