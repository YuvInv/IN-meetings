# Phase 2 · Slice 1 — Calendar Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a meeting finishes, match it to its Google Calendar event, derive attendees (+ internal/external side) and the company, and use that to correct company/fund names in the Hebrew transcript and emit `context.md` priors + fill the reserved `metadata.json` fields — degrading gracefully when there's no match.

**Architecture:** Swift does only the authenticated Calendar fetch (reusing the slice-6 Google OAuth + a new `calendar.events.readonly` scope) and drops candidate events into `<meeting>/context.input.json` before spawning the pipeline. The Python pipeline does everything else — match the event, split internal/external, build the post-correction vocab (`context.vocab.json`, consumed by the *existing* `load_vocab`→`postcorrect` hook), render `context.md`, and merge fields into `metadata.json`. Secrets stay in Swift; Python stays the single writer of the package. No schema change (slice 5 reserved every field).

**Tech Stack:** Python 3.11 (pipeline, `pytest`, `ruff`); Swift 5.9 / macOS 26 app (`INMeetingsCore` SPM + XcodeGen app target); Google Calendar API v3.

**Spec:** `docs/superpowers/specs/2026-06-14-phase2-calendar-context-design.md`

---

## File Structure

**Python (`pipeline/`):**
- Create `in_meetings_pipeline/context_assembler.py` — the whole assembler: load input, match event, split sides, resolve company, transliterate, build vocab, render `context.md`, orchestrate (`assemble`). Owns `AssembledContext`/`Attendee`.
- Create `in_meetings_pipeline/data/core_lexicon.json` — curated always-on entities (the fund name + its observed manglings).
- Modify `in_meetings_pipeline/postcorrect.py` — harden `correct()` to whole-token (boundary-aware) replacement.
- Modify `in_meetings_pipeline/metadata.py` — `build_metadata(..., context=None)` merges calendar fields.
- Modify `in_meetings_pipeline/__main__.py` — call `assemble()` early; pass `context` to `build_metadata`.
- Create `tests/test_context.py`; extend `tests/test_metadata.py`, `tests/test_postcorrect.py` (new).

**Swift:**
- Modify `Sources/INMeetingsCore/Drive/DriveConfig.swift` — add the calendar scope.
- Create `Sources/INMeetingsCore/Calendar/CalendarClient.swift` — Calendar v3 events client (pure URL builder + `send`).
- Create `Sources/INMeetingsCore/Calendar/CalendarContext.swift` — fetch + write `context.input.json`; no-op when not connected.
- Modify `Sources/INMeetingsCore/JobBridge/JobBridge.swift` — fetch calendar context, then spawn.
- Create `Tests/INMeetingsCoreTests/CalendarClientTests.swift`, `Tests/INMeetingsCoreTests/CalendarContextTests.swift`.

**Docs:** `DECISIONS.md` (amends ADR-004), `HANDOFF.md`, `adr/ADR-004-context-assembler.md` (status note).

**Contract — `<meeting>/context.input.json` (Swift → Python):**
```json
{
  "internal_domain": "in-venture.com",
  "hints": { "capture_source_app": "Google Chrome (Meet/web call)",
             "started_at": "2026-06-14T10:00:00Z", "ended_at": "2026-06-14T10:30:00Z" },
  "candidates": [
    { "id": "evt_abc", "summary": "Prelligence <> IN Venture",
      "start": "2026-06-14T10:00:00Z", "end": "2026-06-14T10:30:00Z", "has_link": true,
      "attendees": [ {"email": "yuval@in-venture.com", "displayName": "Yuval Naor", "organizer": true},
                     {"email": "founder@prelligence.com", "displayName": "A Founder", "organizer": false} ] }
  ]
}
```

---

## Task 0: Branch

- [ ] **Step 1: Create the feature branch off main**

We're currently on the merged `feat/slice-6-drive-sync`. Start clean from `main`.

Run:
```bash
cd /Users/yuvalnaor/repos/IN-meetings
git fetch origin && git checkout main && git pull --ff-only && git checkout -b feat/phase2-calendar-context
```
Expected: on a new branch `feat/phase2-calendar-context`.

---

## Task 1: Harden `correct()` to whole-token replacement

**Why:** The seed variants include short/ambiguous tokens (`GM`, `עם Venture`). `postcorrect.correct()` currently does raw substring replacement, which can corrupt larger words. Make it match only whole tokens.

**Files:**
- Modify: `pipeline/in_meetings_pipeline/postcorrect.py`
- Test: `pipeline/tests/test_postcorrect.py` (create)

- [ ] **Step 1: Write the failing test**

Create `pipeline/tests/test_postcorrect.py`:
```python
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_postcorrect.py -v`
Expected: FAIL — `test_does_not_replace_inside_larger_token` fails (current substring replace turns `GMC`→`General MotorsC`).

- [ ] **Step 3: Implement whole-token replacement**

Replace the body of `pipeline/in_meetings_pipeline/postcorrect.py`:
```python
"""Deterministic entity post-correction — the P1-validated biasing mechanism (ADR-004).

Each entity has a canonical spelling + observed variants; a variant is replaced only when it
appears as a whole token (not inside a larger word). Phase-2's context assembler fills the
vocabulary; until it does, an empty vocab makes this a no-op. Mirrors benchmarks/postcorrect.py.
"""

from __future__ import annotations

import re

# A "token char" for boundary purposes: any word char (incl. Hebrew), plus the apostrophe/geresh and
# gershayim that occur *inside* Hebrew transliterations (e.g. נדוויינצ'ר). A variant matches only when
# it is not flanked by one of these — i.e. it stands as a complete token.
_TOKEN = r"[\w'’״׳]"


def correct(text: str, vocab: list[dict]) -> tuple[str, dict]:
    counts: dict[str, int] = {}
    for entry in vocab:
        canon = entry["canonical"]
        for variant in entry.get("variants", []):
            if not variant:
                continue
            pattern = re.compile(rf"(?<!{_TOKEN}){re.escape(variant)}(?!{_TOKEN})")
            new, n = pattern.subn(canon, text)
            if n:
                text = new
                counts[canon] = counts.get(canon, 0) + n
    return text, counts
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_postcorrect.py -v && uvx ruff check in_meetings_pipeline tests`
Expected: PASS (4 tests); ruff clean.

- [ ] **Step 5: Commit**

```bash
git add pipeline/in_meetings_pipeline/postcorrect.py pipeline/tests/test_postcorrect.py
git commit -m "fix(pipeline): whole-token post-correction (boundary-aware) for Phase 2 vocab"
```

---

## Task 2: Core lexicon data + loader

**Files:**
- Create: `pipeline/in_meetings_pipeline/data/core_lexicon.json`
- Modify: `pipeline/in_meetings_pipeline/context_assembler.py` (create with the loader)
- Test: `pipeline/tests/test_context.py` (create)

- [ ] **Step 1: Create the curated lexicon (seeded from real P1 manglings)**

Create `pipeline/in_meetings_pipeline/data/core_lexicon.json` — only entities present in *every* meeting (the fund). Per-company entities come from the calendar at runtime.
```json
[
  {
    "canonical": "IN Venture",
    "variants": ["נדוויינצ'ר", "דווינצ'ר", "עם Venture", "אן וונצ'ר", "אינוונצ'ר", "אין וינצ'ר"]
  }
]
```

- [ ] **Step 2: Write the failing test**

Create `pipeline/tests/test_context.py`:
```python
"""Phase-2 context assembler (ADR-004): match → split → company → vocab → context.md → metadata."""

from __future__ import annotations

from in_meetings_pipeline.context_assembler import load_core_lexicon


def test_core_lexicon_has_fund_name() -> None:
    lex = load_core_lexicon()
    canon = {e["canonical"] for e in lex}
    assert "IN Venture" in canon
    fund = next(e for e in lex if e["canonical"] == "IN Venture")
    assert "נדוויינצ'ר" in fund["variants"]
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -v`
Expected: FAIL — `ModuleNotFoundError: ... context_assembler`.

- [ ] **Step 4: Create the module with the loader**

Create `pipeline/in_meetings_pipeline/context_assembler.py`:
```python
"""Phase-2 context assembler (ADR-004), calendar-first slice.

Swift writes <meeting>/context.input.json (candidate calendar events + hints). This module is the
single owner of everything downstream: pick the matching event, split internal/external attendees,
resolve the company, build the post-correction vocab (context.vocab.json — consumed by the existing
load_vocab→postcorrect hook), render context.md, and return an AssembledContext for metadata merge.

Degrades to first-class no-ops: missing input / no match / errors never block transcription. The
curated core lexicon (the fund name) is applied on *every* meeting, so the highest-frequency error is
fixed even with no calendar match.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

_DATA = Path(__file__).parent / "data"


def load_core_lexicon() -> list[dict]:
    """Always-on curated entities (the fund name + observed manglings)."""
    return json.loads((_DATA / "core_lexicon.json").read_text(encoding="utf-8"))


@dataclass
class Attendee:
    name: str
    email: str | None
    side: str  # "internal" | "external"


@dataclass
class AssembledContext:
    title: str | None = None
    calendar_event_id: str | None = None
    attendees: list[Attendee] = field(default_factory=list)
    company: dict | None = None  # {"name","sevanta_deal_id":None,"dealigence_id":None,"matched":bool}
    calendar_status: str = "empty"  # "ok" | "empty" | "error"
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pipeline/in_meetings_pipeline/context_assembler.py pipeline/in_meetings_pipeline/data/core_lexicon.json pipeline/tests/test_context.py
git commit -m "feat(pipeline): core lexicon + context_assembler scaffold (Phase 2)"
```

---

## Task 3: Match the calendar event

**Files:**
- Modify: `pipeline/in_meetings_pipeline/context_assembler.py`
- Test: `pipeline/tests/test_context.py`

- [ ] **Step 1: Write the failing test**

Append to `pipeline/tests/test_context.py`:
```python
from in_meetings_pipeline.context_assembler import match_event

_WINDOW = ("2026-06-14T10:00:00Z", "2026-06-14T10:30:00Z")


def _evt(eid, start, end, *, link=False, attendees=None):
    return {"id": eid, "summary": "x", "start": start, "end": end,
            "has_link": link, "attendees": attendees or []}


def test_match_picks_greatest_overlap() -> None:
    cands = [
        _evt("a", "2026-06-14T09:00:00Z", "2026-06-14T10:05:00Z"),   # 5 min overlap
        _evt("b", "2026-06-14T10:00:00Z", "2026-06-14T10:30:00Z"),   # full overlap
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -k match -v`
Expected: FAIL — `ImportError: cannot import name 'match_event'`.

- [ ] **Step 3: Implement `match_event`**

Append to `pipeline/in_meetings_pipeline/context_assembler.py`:
```python
from datetime import datetime


def _parse_dt(value: str | None) -> datetime | None:
    """Parse an RFC-3339 timestamp. Date-only (all-day) values return None — they don't pin a meeting."""
    if not value or "T" not in value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _overlap_seconds(a0: datetime, a1: datetime, b0: datetime, b1: datetime) -> float:
    return max(0.0, (min(a1, b1) - max(a0, b0)).total_seconds())


def match_event(candidates: list[dict], started_at: str, ended_at: str) -> dict | None:
    """Pick the candidate whose [start,end] overlaps the recording window most (overlap must be > 0).
    Tie-break toward events with a conferencing link, then with external-looking attendee lists."""
    w0, w1 = _parse_dt(started_at), _parse_dt(ended_at)
    if w0 is None or w1 is None:
        return None
    best: tuple | None = None
    for ev in candidates:
        s, e = _parse_dt(ev.get("start")), _parse_dt(ev.get("end"))
        if s is None or e is None:
            continue
        ov = _overlap_seconds(s, e, w0, w1)
        if ov <= 0:
            continue
        key = (ov, bool(ev.get("has_link")), len(ev.get("attendees") or []))
        if best is None or key > best[0]:
            best = (key, ev)
    return best[1] if best else None
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -k match -v`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add pipeline/in_meetings_pipeline/context_assembler.py pipeline/tests/test_context.py
git commit -m "feat(pipeline): match recording to calendar event by time overlap"
```

---

## Task 4: Split internal/external + resolve company

**Files:**
- Modify: `pipeline/in_meetings_pipeline/context_assembler.py`
- Test: `pipeline/tests/test_context.py`

- [ ] **Step 1: Write the failing test**

Append to `pipeline/tests/test_context.py`:
```python
from in_meetings_pipeline.context_assembler import resolve_company, split_sides

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
    # name falls back to the email local-part when displayName is absent
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -k "split or company" -v`
Expected: FAIL — import error for `split_sides`/`resolve_company`.

- [ ] **Step 3: Implement**

Append to `pipeline/in_meetings_pipeline/context_assembler.py`:
```python
from collections import Counter

# Public email providers are never a company identity.
_PUBLIC_DOMAINS = {"gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "yahoo.com", "icloud.com"}


def _domain(email: str | None) -> str | None:
    if not email or "@" not in email:
        return None
    return email.rsplit("@", 1)[1].lower()


def _name_from(att: dict) -> str:
    return att.get("displayName") or (att.get("email") or "").split("@", 1)[0] or "Unknown"


def split_sides(event: dict, internal_domain: str) -> list[Attendee]:
    """Attendees with side = internal when their email domain matches the signed-in account's domain."""
    out: list[Attendee] = []
    for att in event.get("attendees") or []:
        dom = _domain(att.get("email"))
        side = "internal" if dom == internal_domain.lower() else "external"
        out.append(Attendee(name=_name_from(att), email=att.get("email"), side=side))
    return out


def _company_name_from_domain(domain: str) -> str:
    """prelligence.com → Prelligence; get-foo.io → Get Foo."""
    label = domain.split(".")[0]
    return " ".join(part.capitalize() for part in label.replace("_", "-").split("-") if part)


def resolve_company(attendees: list[Attendee], title: str | None) -> dict | None:
    """Company = the dominant non-public external email domain; else None. matched:false (no CRM here)."""
    domains = [d for a in attendees if a.side == "external"
               if (d := _domain(a.email)) and d not in _PUBLIC_DOMAINS]
    if not domains:
        return None
    dominant = Counter(domains).most_common(1)[0][0]
    return {"name": _company_name_from_domain(dominant),
            "sevanta_deal_id": None, "dealigence_id": None, "matched": False}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -k "split or company" -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add pipeline/in_meetings_pipeline/context_assembler.py pipeline/tests/test_context.py
git commit -m "feat(pipeline): internal/external split + company resolution from attendee domains"
```

---

## Task 5: Transliteration candidates + `build_vocab`

**Why:** The per-meeting company entry needs Hebrew variant candidates so its Latin canonical can be restored from the model's Hebrew rendering. This is **best-effort** (P1 showed the worst manglings aren't clean transliterations); the curated core lexicon is the guaranteed win. Candidates are length-guarded (≥4) and applied whole-token (Task 1) to avoid false replacements.

**Files:**
- Modify: `pipeline/in_meetings_pipeline/context_assembler.py`
- Test: `pipeline/tests/test_context.py`

- [ ] **Step 1: Write the failing test**

Append to `pipeline/tests/test_context.py`:
```python
from in_meetings_pipeline.context_assembler import build_vocab, hebrew_transliteration_candidates


def test_transliteration_is_length_guarded() -> None:
    # 2-letter tokens are too risky to auto-transliterate.
    assert hebrew_transliteration_candidates("GM") == []
    cands = hebrew_transliteration_candidates("Prelligence")
    assert cands and all(len(c) >= 4 for c in cands)


def test_build_vocab_includes_core_and_company() -> None:
    company = {"name": "Prelligence", "matched": False}
    vocab = build_vocab(company)
    canon = {e["canonical"] for e in vocab}
    assert "IN Venture" in canon          # always-on core lexicon
    assert "Prelligence" in canon         # per-meeting company
    pr = next(e for e in vocab if e["canonical"] == "Prelligence")
    assert pr["variants"]                  # at least one Hebrew candidate


def test_build_vocab_core_only_when_no_company() -> None:
    vocab = build_vocab(None)
    assert {e["canonical"] for e in vocab} == {"IN Venture"}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -k "translit or vocab" -v`
Expected: FAIL — import error.

- [ ] **Step 3: Implement**

Append to `pipeline/in_meetings_pipeline/context_assembler.py`:
```python
# Best-effort Latin→Hebrew phonetic map (single most-common rendering per letter). Deliberately small;
# real coverage comes from the curated lexicon now and accumulated observed variants later (deferred).
_TRANSLIT = {
    "a": "א", "b": "ב", "c": "ק", "d": "ד", "e": "", "f": "פ", "g": "ג", "h": "ה", "i": "י",
    "j": "ג'", "k": "ק", "l": "ל", "m": "מ", "n": "נ", "o": "ו", "p": "פ", "q": "ק", "r": "ר",
    "s": "ס", "t": "ט", "u": "ו", "v": "ו", "w": "ו", "x": "קס", "y": "י", "z": "ז",
}


def hebrew_transliteration_candidates(latin: str) -> list[str]:
    """One best-effort Hebrew spelling of a Latin word, guarded to ≥4 chars (shorter is too risky)."""
    word = "".join(ch for ch in latin if ch.isalpha() or ch == " ")
    if len(word.replace(" ", "")) < 4:
        return []
    heb = "".join(_TRANSLIT.get(ch.lower(), ch if ch == " " else "") for ch in word).strip()
    return [heb] if len(heb) >= 4 else []


def build_vocab(company: dict | None) -> list[dict]:
    """Post-correction vocab: the always-on core lexicon + (when matched) the meeting's company."""
    vocab = load_core_lexicon()
    if company and company.get("name"):
        name = company["name"]
        variants = hebrew_transliteration_candidates(name)
        if variants:
            vocab = vocab + [{"canonical": name, "variants": variants}]
    return vocab
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -k "translit or vocab" -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add pipeline/in_meetings_pipeline/context_assembler.py pipeline/tests/test_context.py
git commit -m "feat(pipeline): best-effort transliteration + build_vocab (core + company)"
```

---

## Task 6: Render `context.md`

**Files:**
- Modify: `pipeline/in_meetings_pipeline/context_assembler.py`
- Test: `pipeline/tests/test_context.py`

- [ ] **Step 1: Write the failing test**

Append to `pipeline/tests/test_context.py`:
```python
from in_meetings_pipeline.context_assembler import AssembledContext, render_context_md


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
```
Add the missing import at the top of the test file:
```python
from in_meetings_pipeline.context_assembler import Attendee
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -k context_md -v`
Expected: FAIL — import error for `render_context_md`.

- [ ] **Step 3: Implement**

Append to `pipeline/in_meetings_pipeline/context_assembler.py`:
```python
_WALL = (
    "# Meeting context — PRIORS ONLY\n"
    "> Identity & logistics assembled from the calendar. NOT meeting content.\n"
    "> Deal narrative, decisions, and quotes must come ONLY from the transcript.\n"
)


def render_context_md(ctx: AssembledContext) -> str:
    if ctx.calendar_status != "ok":
        return _WALL + "\nNo calendar event matched; priors unavailable.\n"
    lines = [_WALL, ""]
    if ctx.title:
        lines.append(f"**Meeting:** {ctx.title}")
    if ctx.calendar_event_id:
        lines.append(f"**Source:** Google Calendar (event {ctx.calendar_event_id})")
    internal = [a for a in ctx.attendees if a.side == "internal"]
    external = [a for a in ctx.attendees if a.side == "external"]
    if internal:
        lines += ["", "## IN Venture (internal)"] + [f"- {a.name} {a.email or ''}".rstrip() for a in internal]
    if external:
        company = (ctx.company or {}).get("name") or "External"
        lines += ["", f"## {company} (external)"] + [f"- {a.name} {a.email or ''}".rstrip() for a in external]
    if ctx.company and ctx.company.get("name"):
        lines += ["", "## Company",
                  f"- **{ctx.company['name']}** — inferred from the calendar. Not yet linked to a CRM deal "
                  "(matched: false)."]
    return "\n".join(lines) + "\n"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -k context_md -v`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add pipeline/in_meetings_pipeline/context_assembler.py pipeline/tests/test_context.py
git commit -m "feat(pipeline): render context.md priors (with the priors/content wall)"
```

---

## Task 7: `assemble()` orchestration + degradation

**Files:**
- Modify: `pipeline/in_meetings_pipeline/context_assembler.py`
- Test: `pipeline/tests/test_context.py`

- [ ] **Step 1: Write the failing test**

Append to `pipeline/tests/test_context.py`:
```python
import json
from pathlib import Path

from in_meetings_pipeline.context_assembler import assemble


def _write_input(directory: Path, candidates, internal_domain="in-venture.com") -> None:
    payload = {"internal_domain": internal_domain,
               "hints": {"started_at": "2026-06-14T10:00:00Z", "ended_at": "2026-06-14T10:30:00Z"},
               "candidates": candidates}
    (directory / "context.input.json").write_text(json.dumps(payload), encoding="utf-8")


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
    # the fund-name fix still ships on every meeting
    vocab = json.loads((tmp_path / "context.vocab.json").read_text(encoding="utf-8"))
    assert {e["canonical"] for e in vocab} == {"IN Venture"}


def test_assemble_no_overlap_is_empty(tmp_path: Path) -> None:
    _write_input(tmp_path, [{"id": "x", "summary": "s",
                             "start": "2026-06-14T08:00:00Z", "end": "2026-06-14T09:00:00Z",
                             "has_link": False, "attendees": []}])
    ctx = assemble(tmp_path)
    assert ctx.calendar_status == "empty"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -k assemble -v`
Expected: FAIL — import error for `assemble`.

- [ ] **Step 3: Implement**

Append to `pipeline/in_meetings_pipeline/context_assembler.py`:
```python
import sys


def assemble(directory: Path) -> AssembledContext:
    """Orchestrate the calendar-first assembler. Always writes context.vocab.json (≥ core lexicon) and
    context.md; returns an AssembledContext for the metadata merge. Never raises — failures degrade."""
    ctx = AssembledContext()
    company: dict | None = None
    try:
        input_path = directory / "context.input.json"
        if input_path.exists():
            data = json.loads(input_path.read_text(encoding="utf-8"))
            internal_domain = data.get("internal_domain") or ""
            hints = data.get("hints") or {}
            event = match_event(data.get("candidates") or [],
                                hints.get("started_at") or "", hints.get("ended_at") or "")
            if event is not None:
                attendees = split_sides(event, internal_domain)
                company = resolve_company(attendees, event.get("summary"))
                ctx = AssembledContext(title=event.get("summary"), calendar_event_id=event.get("id"),
                                       attendees=attendees, company=company, calendar_status="ok")
    except Exception as exc:  # noqa: BLE001 — the assembler must never fail the pipeline
        print(f"context assembler degraded ({type(exc).__name__}: {exc})", file=sys.stderr)
        ctx = AssembledContext(calendar_status="error")

    (directory / "context.vocab.json").write_text(
        json.dumps(build_vocab(company), ensure_ascii=False, indent=2), encoding="utf-8")
    (directory / "context.md").write_text(render_context_md(ctx), encoding="utf-8")
    return ctx
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -v && uvx ruff check in_meetings_pipeline tests`
Expected: PASS (all `test_context.py`); ruff clean.

- [ ] **Step 5: Commit**

```bash
git add pipeline/in_meetings_pipeline/context_assembler.py pipeline/tests/test_context.py
git commit -m "feat(pipeline): assemble() orchestration with first-class degradation"
```

---

## Task 8: Merge calendar fields into `metadata.json`

**Files:**
- Modify: `pipeline/in_meetings_pipeline/metadata.py`
- Test: `pipeline/tests/test_metadata.py`

- [ ] **Step 1: Write the failing test**

Append to `pipeline/tests/test_metadata.py`:
```python
from in_meetings_pipeline.context_assembler import AssembledContext, Attendee


def test_build_metadata_merges_calendar_context(tmp_path: Path) -> None:
    mic = _wav(tmp_path / "mic.wav", 1.0)
    job = Job("2026-06-14-1000", tmp_path, "call", mic, None, capture_source_app="Chrome")
    ctx = AssembledContext(
        title="Prelligence <> IN Venture", calendar_event_id="e1",
        attendees=[Attendee("Yuval", "yuval@in-venture.com", "internal"),
                   Attendee("Founder", "founder@prelligence.com", "external")],
        company={"name": "Prelligence", "sevanta_deal_id": None, "dealigence_id": None, "matched": False},
        calendar_status="ok")

    md = build_metadata(job, engine="whisper.cpp", model_revision="rev", language="he",
                        biased=True, vocabulary_terms_used=["IN Venture"], context=ctx)

    assert md["meeting"]["title"] == "Prelligence <> IN Venture"
    assert md["meeting"]["calendar_event_id"] == "e1"
    assert md["company"]["name"] == "Prelligence"
    assert {a["side"] for a in md["attendees"]} == {"internal", "external"}
    assert md["attendees"][0]["matched_crm_contact_id"] is None
    assert md["context"]["sources"]["calendar"] == "ok"


def test_build_metadata_without_context_is_unchanged(tmp_path: Path) -> None:
    mic = _wav(tmp_path / "mic.wav", 1.0)
    job = Job("2026-06-14-1000", tmp_path, "call", mic, None)
    md = build_metadata(job, engine="e", model_revision="r", language="he", biased=False)
    assert md["attendees"] == []
    assert md["context"]["sources"]["calendar"] == "empty"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_metadata.py -k context -v`
Expected: FAIL — `build_metadata() got an unexpected keyword argument 'context'`.

- [ ] **Step 3: Implement**

In `pipeline/in_meetings_pipeline/metadata.py`, add the import near the top:
```python
from .context_assembler import AssembledContext
```
Change the `build_metadata` signature to accept the context:
```python
def build_metadata(
    job: Job,
    *,
    engine: str,
    model_revision: str,
    language: str,
    biased: bool,
    vocabulary_terms_used: list[str] | None = None,
    context: AssembledContext | None = None,
) -> dict:
```
Then, just before the `return {`, compute the calendar-derived blocks:
```python
    cal_status = context.calendar_status if context else "empty"
    title = context.title if context else None
    event_id = context.calendar_event_id if context else None
    attendees = (
        [{"name": a.name, "email": a.email, "side": a.side, "matched_crm_contact_id": None}
         for a in context.attendees]
        if context else []
    )
    company = (
        context.company if (context and context.company)
        else {"name": None, "sevanta_deal_id": None, "dealigence_id": None, "matched": False}
    )
```
Update the returned dict's `meeting`, `attendees`, `company`, and `context` blocks to use them:
```python
        "meeting": {
            "title": title,
            "start": start,
            "end": end,
            "type": _PROFILE_TO_TYPE.get(job.profile, "call"),
            "calendar_event_id": event_id,
        },
        "attendees": attendees,
        "company": company,
        ...
        "context": {
            "sources": {"calendar": cal_status, "saventa": "empty", "dealigence": "empty"},
        },
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_metadata.py -v && uvx ruff check in_meetings_pipeline tests`
Expected: PASS (all metadata tests incl. the originals); ruff clean.

- [ ] **Step 5: Commit**

```bash
git add pipeline/in_meetings_pipeline/metadata.py pipeline/tests/test_metadata.py
git commit -m "feat(pipeline): merge calendar context into metadata.json"
```

---

## Task 9: Wire the assembler into the pipeline run

**Files:**
- Modify: `pipeline/in_meetings_pipeline/__main__.py`
- Test: `pipeline/tests/test_context.py` (a wiring test that doesn't need whisper)

- [ ] **Step 1: Write the failing test**

Append to `pipeline/tests/test_context.py` — assert the run wires `assemble` before packaging by checking that, given an input file, a no-track job still produces the artifacts (transcription is skipped when there are no WAVs, so this exercises the wiring without whisper):
```python
from in_meetings_pipeline.__main__ import run
from in_meetings_pipeline.job import Job


def test_run_invokes_assembler_and_packages(tmp_path: Path, monkeypatch) -> None:
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -k run_invokes -v`
Expected: FAIL — `metadata.json` has `calendar_event_id: null` (assembler not yet wired into `run`).

- [ ] **Step 3: Implement the wiring**

In `pipeline/in_meetings_pipeline/__main__.py`:

Add the import alongside the others:
```python
from .context_assembler import assemble
```
In `run()`, right after `status.write("queued", 0.0)`, assemble the context (it writes `context.vocab.json` + `context.md`, which the existing `load_vocab`→post-correct path then picks up):
```python
        status.write("queued", 0.0)
        ctx = assemble(job.directory)
```
Pass it to `build_metadata` (the only change to that call):
```python
                build_metadata(
                    job,
                    engine=ENGINE,
                    model_revision=rev,
                    language="he",
                    biased=biased,
                    vocabulary_terms_used=terms,
                    context=ctx,
                ),
```

- [ ] **Step 4: Run the full pipeline suite**

Run: `cd pipeline && .venv/bin/python -m pytest tests/ -v && uvx ruff check in_meetings_pipeline tests`
Expected: PASS (all suites: postcorrect, context, metadata, transcript, diarize, contract); ruff clean.

- [ ] **Step 5: Commit**

```bash
git add pipeline/in_meetings_pipeline/__main__.py pipeline/tests/test_context.py
git commit -m "feat(pipeline): run the context assembler before transcription + packaging"
```

---

## Task 10: Add the Calendar OAuth scope

**Files:**
- Modify: `Sources/INMeetingsCore/Drive/DriveConfig.swift`
- Test: `Tests/INMeetingsCoreTests/CalendarClientTests.swift` (create — start with the scope assertion)

- [ ] **Step 1: Write the failing test**

Create `Tests/INMeetingsCoreTests/CalendarClientTests.swift`:
```swift
import XCTest
@testable import INMeetingsCore

final class CalendarClientTests: XCTestCase {
    func testOAuthScopesIncludeCalendarReadonly() {
        XCTAssertTrue(DriveConfig.oauth.scopes.contains("https://www.googleapis.com/auth/calendar.events.readonly"))
        XCTAssertTrue(DriveConfig.oauth.scopes.contains("https://www.googleapis.com/auth/drive"))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter CalendarClientTests/testOAuthScopesIncludeCalendarReadonly`
Expected: FAIL — calendar scope missing.

- [ ] **Step 3: Add the scope**

In `Sources/INMeetingsCore/Drive/DriveConfig.swift`, update `scopes`:
```swift
        scopes: [
            "https://www.googleapis.com/auth/drive",
            "https://www.googleapis.com/auth/calendar.events.readonly",
        ]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CalendarClientTests/testOAuthScopesIncludeCalendarReadonly`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/INMeetingsCore/Drive/DriveConfig.swift Tests/INMeetingsCoreTests/CalendarClientTests.swift
git commit -m "feat(app): request calendar.events.readonly scope (Phase 2)"
```

> Note: existing connected users must reconnect once to grant the new scope. This re-consent is also the moment to live-verify the still-unverified slice-6 sign-in.

---

## Task 11: `CalendarClient` (pure request building + events fetch)

**Files:**
- Create: `Sources/INMeetingsCore/Calendar/CalendarClient.swift`
- Test: `Tests/INMeetingsCoreTests/CalendarClientTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/INMeetingsCoreTests/CalendarClientTests.swift`:
```swift
    func testEventsURLBuildsWindowedPrimaryQuery() throws {
        let min = Date(timeIntervalSince1970: 1_780_000_000)
        let max = Date(timeIntervalSince1970: 1_780_003_600)
        let url = CalendarClient.eventsURL(timeMin: min, timeMax: max)
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertTrue(url.path.hasSuffix("/calendars/primary/events"))
        let q = Dictionary(uniqueKeysWithValues: comps.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["singleEvents"], "true")
        XCTAssertEqual(q["orderBy"], "startTime")
        XCTAssertNotNil(q["timeMin"]); XCTAssertNotNil(q["timeMax"])
        XCTAssertTrue((q["fields"] ?? "").contains("attendees"))
    }

    func testDecodesEventsResponse() throws {
        let json = """
        {"items":[{"id":"e1","summary":"Prelligence <> IN Venture",
          "start":{"dateTime":"2026-06-14T10:00:00Z"},"end":{"dateTime":"2026-06-14T10:30:00Z"},
          "hangoutLink":"https://meet.google.com/x",
          "attendees":[{"email":"founder@prelligence.com","displayName":"Founder","organizer":false}]}]}
        """.data(using: .utf8)!
        let events = try CalendarClient.decodeEvents(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].id, "e1")
        XCTAssertEqual(events[0].start.dateTime, "2026-06-14T10:00:00Z")
        XCTAssertEqual(events[0].attendees?.first?.email, "founder@prelligence.com")
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter CalendarClientTests`
Expected: FAIL — `CalendarClient` undefined.

- [ ] **Step 3: Implement the client**

Create `Sources/INMeetingsCore/Calendar/CalendarClient.swift`:
```swift
import Foundation

public enum CalendarError: Error, Sendable { case http(status: Int, body: String) }

/// Minimal Google Calendar v3 client. Like `DriveClient`, the request building + decoding are pure
/// static helpers (unit-tested); execution goes through an injected token provider + `URLSession`.
public final class CalendarClient: @unchecked Sendable {
    public typealias TokenProvider = @Sendable () async throws -> String

    private let token: TokenProvider
    private let session: URLSession

    public init(token: @escaping TokenProvider, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    static let apiBase = URL(string: "https://www.googleapis.com/calendar/v3")!
    static let fields = "items(id,summary,start,end,hangoutLink,attendees(email,displayName,organizer,self))"

    // MARK: - Pure helpers (unit-tested)

    /// Windowed events query on the user's `primary` calendar (timed, expanded, time-ordered).
    static func eventsURL(timeMin: Date, timeMax: Date) -> URL {
        let iso = ISO8601DateFormatter()
        var c = URLComponents(url: apiBase.appendingPathComponent("calendars/primary/events"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: timeMin)),
            URLQueryItem(name: "timeMax", value: iso.string(from: timeMax)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "fields", value: fields),
        ]
        return c.url!
    }

    static func decodeEvents(_ data: Data) throws -> [CalendarEvent] {
        try JSONDecoder().decode(EventsResponse.self, from: data).items
    }

    // MARK: - API

    public func fetchEvents(timeMin: Date, timeMax: Date) async throws -> [CalendarEvent] {
        var request = URLRequest(url: Self.eventsURL(timeMin: timeMin, timeMax: timeMax))
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CalendarError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try Self.decodeEvents(data)
    }
}

public struct CalendarEvent: Decodable, Sendable {
    public struct When: Decodable, Sendable { public let dateTime: String?; public let date: String? }
    public struct Attendee: Decodable, Sendable {
        public let email: String?
        public let displayName: String?
        public let organizer: Bool?
        public let `self`: Bool?
    }
    public let id: String
    public let summary: String?
    public let start: When
    public let end: When
    public let hangoutLink: String?
    public let attendees: [Attendee]?
}

struct EventsResponse: Decodable { let items: [CalendarEvent] }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CalendarClientTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/INMeetingsCore/Calendar/CalendarClient.swift Tests/INMeetingsCoreTests/CalendarClientTests.swift
git commit -m "feat(app): Google Calendar v3 events client (Phase 2)"
```

---

## Task 12: `CalendarContext` — fetch + write `context.input.json`

**Files:**
- Create: `Sources/INMeetingsCore/Calendar/CalendarContext.swift`
- Test: `Tests/INMeetingsCoreTests/CalendarContextTests.swift` (create)

- [ ] **Step 1: Write the failing test (pure payload shaping + domain)**

Create `Tests/INMeetingsCoreTests/CalendarContextTests.swift`:
```swift
import XCTest
@testable import INMeetingsCore

final class CalendarContextTests: XCTestCase {
    func testDomainOfEmail() {
        XCTAssertEqual(CalendarContext.domain(ofEmail: "Yuval@IN-Venture.com"), "in-venture.com")
        XCTAssertEqual(CalendarContext.domain(ofEmail: "broken"), "")
    }

    func testInputPayloadFlattensEventsAndHints() throws {
        let ev = CalendarEvent(
            id: "e1", summary: "Prelligence <> IN Venture",
            start: .init(dateTime: "2026-06-14T10:00:00Z", date: nil),
            end: .init(dateTime: "2026-06-14T10:30:00Z", date: nil),
            hangoutLink: "https://meet.google.com/x",
            attendees: [.init(email: "founder@prelligence.com", displayName: "Founder",
                              organizer: false, self: false)])
        let payload = CalendarContext.inputPayload(
            internalDomain: "in-venture.com", candidates: [ev],
            captureSourceApp: "Chrome",
            startedAt: Date(timeIntervalSince1970: 1_780_000_000),
            endedAt: Date(timeIntervalSince1970: 1_780_001_800))

        XCTAssertEqual(payload["internal_domain"] as? String, "in-venture.com")
        let hints = payload["hints"] as! [String: Any]
        XCTAssertEqual(hints["capture_source_app"] as? String, "Chrome")
        let cands = payload["candidates"] as! [[String: Any]]
        XCTAssertEqual(cands.first?["id"] as? String, "e1")
        XCTAssertEqual(cands.first?["start"] as? String, "2026-06-14T10:00:00Z")
        XCTAssertEqual(cands.first?["has_link"] as? Bool, true)
        let atts = cands.first?["attendees"] as! [[String: Any]]
        XCTAssertEqual(atts.first?["email"] as? String, "founder@prelligence.com")
    }
}
```
> `CalendarEvent`/`When`/`Attendee` need memberwise inits usable from tests. They're structs with `let`s, so the synthesized memberwise init is internal — fine for `@testable import`. If the compiler rejects the `.init(...)` calls (public struct, internal init), add explicit `public init`s to `CalendarEvent`, `When`, and `Attendee` in Task 11's file.

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter CalendarContextTests`
Expected: FAIL — `CalendarContext` undefined.

- [ ] **Step 3: Implement**

Create `Sources/INMeetingsCore/Calendar/CalendarContext.swift`:
```swift
import Foundation
import os

private let calendarLog = Logger(subsystem: "com.in-venture.in-meetings", category: "calendar")

/// Phase-2 calendar context (ADR-004), Swift half: fetch candidate events around the meeting window and
/// write `<meeting>/context.input.json` for the Python assembler. Reuses the slice-6 Google credential.
/// A no-op when no account is connected or anything fails — the pipeline then degrades to unbiased.
public final class CalendarContext: @unchecked Sendable {
    private let tokenStore: TokenStore
    private let client: CalendarClient

    public init(tokenStore: TokenStore = KeychainTokenStore(),
                session: URLSession = CalendarContext.defaultSession) {
        self.tokenStore = tokenStore
        let oauth = GoogleOAuth(config: DriveConfig.oauth)
        let tokenService = GoogleTokenService(session: session)
        let tokens = DriveTokenManager(oauth: oauth, store: tokenStore,
                                       refresher: { try await tokenService.post($0) })
        self.client = CalendarClient(token: { try await tokens.validAccessToken() }, session: session)
    }

    /// A short-timeout session — the fetch sits in front of pipeline spawn, so it must not stall Stop.
    public static var defaultSession: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config)
    }

    public var isConnected: Bool { tokenStore.load() != nil }

    /// Fetch candidates for `[startedAt-90m, endedAt+30m]` and write context.input.json. Best-effort.
    public func writeInput(into directory: URL, startedAt: Date, endedAt: Date,
                           captureSourceApp: String?) async {
        guard let credential = tokenStore.load() else { return }
        let domain = Self.domain(ofEmail: credential.account)
        do {
            let events = try await client.fetchEvents(timeMin: startedAt.addingTimeInterval(-90 * 60),
                                                      timeMax: endedAt.addingTimeInterval(30 * 60))
            let payload = Self.inputPayload(internalDomain: domain, candidates: events,
                                            captureSourceApp: captureSourceApp,
                                            startedAt: startedAt, endedAt: endedAt)
            let data = try JSONSerialization.data(withJSONObject: payload,
                                                  options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("context.input.json"), options: .atomic)
            calendarLog.notice("calendar context written (\(events.count, privacy: .public) candidates)")
        } catch {
            calendarLog.error("calendar context skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Pure helpers (unit-tested)

    static func domain(ofEmail email: String) -> String {
        guard let at = email.firstIndex(of: "@") else { return "" }
        return email[email.index(after: at)...].lowercased()
    }

    static func inputPayload(internalDomain: String, candidates: [CalendarEvent],
                             captureSourceApp: String?, startedAt: Date, endedAt: Date) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        let cands: [[String: Any]] = candidates.map { ev in
            [
                "id": ev.id,
                "summary": ev.summary ?? "",
                "start": ev.start.dateTime ?? ev.start.date ?? "",
                "end": ev.end.dateTime ?? ev.end.date ?? "",
                "has_link": ev.hangoutLink != nil,
                "attendees": (ev.attendees ?? []).map { att in
                    ["email": att.email ?? "", "displayName": att.displayName ?? "",
                     "organizer": att.organizer ?? false] as [String: Any]
                },
            ]
        }
        return [
            "internal_domain": internalDomain,
            "hints": ["capture_source_app": captureSourceApp ?? "",
                      "started_at": iso.string(from: startedAt),
                      "ended_at": iso.string(from: endedAt)],
            "candidates": cands,
        ]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CalendarContextTests`
Expected: PASS (2 tests). If the `.init` calls failed to compile, add the `public init`s noted in Step 1 and re-run.

- [ ] **Step 5: Commit**

```bash
git add Sources/INMeetingsCore/Calendar/CalendarContext.swift Tests/INMeetingsCoreTests/CalendarContextTests.swift Sources/INMeetingsCore/Calendar/CalendarClient.swift
git commit -m "feat(app): CalendarContext writes context.input.json for the pipeline (Phase 2)"
```

---

## Task 13: Fetch calendar context before spawning the pipeline

**Files:**
- Modify: `Sources/INMeetingsCore/JobBridge/JobBridge.swift`

- [ ] **Step 1: Add the collaborator + fetch-then-spawn**

In `JobBridge`, add a lazy `CalendarContext` next to `driveBackup`:
```swift
    /// Phase-2 calendar context — fetched before spawn so the assembler has its input. No-op until the
    /// user connects a Google account (same credential as Drive).
    @ObservationIgnored private lazy var calendarContext: CalendarContext? = CalendarContext()
```
In `enqueue(...)`, replace the final `spawn(...)` call with a fetch-then-spawn. Change:
```swift
        spawn(jobURL: jobURL, statusURL: dir.appendingPathComponent("status.json"))
```
to:
```swift
        let statusURL = dir.appendingPathComponent("status.json")
        Task { @MainActor in
            await self.calendarContext?.writeInput(into: dir, startedAt: startedAt, endedAt: endedAt,
                                                   captureSourceApp: captureSourceApp)
            self.spawn(jobURL: jobURL, statusURL: statusURL)
        }
```
> The 5s session timeout (Task 12) bounds the wait; on failure no `context.input.json` is written and the pipeline degrades. `phase`/`lastError` are still set synchronously before the Task, so the UI reflects "processing" immediately.

- [ ] **Step 2: Build the package**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Run the Core test suite**

Run: `swift test`
Expected: PASS — all existing + new Core tests (42 from slices 5–6, plus the 5 new calendar tests).

- [ ] **Step 4: Commit**

```bash
git add Sources/INMeetingsCore/JobBridge/JobBridge.swift
git commit -m "feat(app): fetch calendar context before spawning the pipeline (Phase 2)"
```

---

## Task 14: Regenerate the app project + full app build

**Files:** none (build only — new app-target source files aren't auto-picked-up).

- [ ] **Step 1: Regenerate + build the full app**

New files under `Sources/INMeetingsCore/` are picked up by SPM automatically, so `make gen` is only needed if a *new app-target* file was added. This slice added Core files only — but run `make gen` defensively, then build.

Run: `make gen && make build-mac`
Expected: XcodeGen regenerates; `xcodebuild` succeeds (BUILD SUCCEEDED).

- [ ] **Step 2: Run the app test target**

Run: `make test`
Expected: PASS.

- [ ] **Step 3: Commit any project.yml/pbxproj changes (if `make gen` changed them)**

```bash
git add -A && git status --short
git commit -m "chore(app): regenerate project for Phase 2 calendar context" || echo "nothing to commit"
```

---

## Task 15: Docs — DECISIONS, ADR-004 note, HANDOFF

**Files:**
- Modify: `DECISIONS.md`, `adr/ADR-004-context-assembler.md`, `HANDOFF.md`

- [ ] **Step 1: Append the decision (amends ADR-004)**

Add to `DECISIONS.md` (newest last):
```markdown
### 2026-06-14 — Phase 2 slice 1: calendar context assembler — Swift fetch / Python transform (amends ADR-004)
- **Agent**: Claude Code (design by Yuval)
- **Decision**: First Phase-2 sub-slice = Google Calendar only. Swift fetches candidate events (slice-6
  Google OAuth + new `calendar.events.readonly` scope) and writes `<meeting>/context.input.json` before
  spawning the pipeline; the Python pipeline matches the event, splits internal/external by the signed-in
  account's domain, builds the post-correction vocab (`context.vocab.json`, consumed by the existing
  `load_vocab`→`postcorrect` hook), renders `context.md`, and merges fields into `metadata.json`. The
  curated **core lexicon** (the fund name "IN Venture") is applied on every meeting; per-company variants
  are best-effort transliterations (partial by design — accumulation deferred). Personal names are priors
  only (not rewritten). Post-correction hardened to whole-token.
- **Amends ADR-004**: (a) the assembler is **not** "the Python pipeline calling MCP servers" — a headless
  subprocess can't reach MCP; credentialed fetch is Swift-side. (b) "Run parallel with capture so vocab is
  ready before ASR" is relaxed — P1 made post-correction (post-ASR) the mechanism, so the assembler is a
  post-spawn pipeline step. Saventa + Dealigence deferred to slice 2.
- **Consequences**: adding the calendar scope forces a one-time Google re-consent (also the moment to
  live-verify the slice-6 sign-in). No schema change (slice 5 reserved every field). New deps: none.
```

- [ ] **Step 2: Mark ADR-004 amended**

At the top of `adr/ADR-004-context-assembler.md`, under the status line, add:
```markdown
> **Amended 2026-06-14 (Phase 2 slice 1):** mechanism = post-correction (not `initial_prompt`); runtime =
> Swift fetch / Python transform (not pipeline-calls-MCP); calendar-first (Saventa/Dealigence = slice 2).
> See `DECISIONS.md` 2026-06-14 and `docs/superpowers/specs/2026-06-14-phase2-calendar-context-design.md`.
```

- [ ] **Step 3: Update HANDOFF "Current State" + "Next"**

Replace the relevant parts of `HANDOFF.md` to record: Phase 2 slice 1 code-complete (calendar context), Python + Swift tests green, **pending live-verify** (real call with a calendar event → `context.md` + corrected names + metadata; plus a no-match call). Keep the slice-6 live-verify note (now reachable via the calendar re-consent).

- [ ] **Step 4: Commit**

```bash
git add DECISIONS.md adr/ADR-004-context-assembler.md HANDOFF.md
git commit -m "docs: record Phase 2 slice 1 (calendar context) decisions + handoff"
```

---

## Task 16: Live verification (per the verify-each-slice rule)

> **BUILD SUCCEEDED is not verification.** This task is manual and must be done before the slice is "done".

- [ ] **Step 1: P1 eval re-run (offline, proves the correction path)**

With a hand-built `context.input.json` pointing at the Prelligence event (or by feeding the P1 transcript through the integrated post-correct), confirm `נדוויינצ'ר → IN Venture` and the company fixes appear vs. the unbiased baseline (`pipeline/benchmarks/results/prelligence_6min_noprompt.txt`).

- [ ] **Step 2: Live call WITH a calendar event**
  1. `make run-mac`; in the menu, **reconnect Google** (grants the new calendar scope — watch the sign-in sheet; this also live-verifies slice 6).
  2. Put a matching event on your `primary` calendar; record a short real call.
  3. After processing, confirm in the meeting folder: `context.md` lists the right attendees by side + company; `transcript.txt` shows the fund/company name corrected; `metadata.json` has `attendees[]`, `company`, `meeting.title`, `context.sources.calendar: "ok"`, `transcription.biased: true`.

- [ ] **Step 3: Live call with NO calendar event (degradation)**

Record a short call with nothing on the calendar; confirm transcription still completes, `context.md` says "No calendar event matched", `metadata.context.sources.calendar: "empty"`, and the fund-name correction still applied (core lexicon).

- [ ] **Step 4: Update HANDOFF/DECISIONS with the live-verify result, then open the PR**

```bash
git push -u origin feat/phase2-calendar-context
gh pr create --fill --base main
```

---

## Self-Review (completed by plan author)

**1. Spec coverage:**
- Calendar fetch + scope → Tasks 10–12. Match + split + company → Tasks 3–4. Vocab + post-correct → Tasks 1, 2, 5. context.md → Task 6. Metadata fields → Task 8. Orchestration + degradation → Task 7. Wiring (Swift→file→Python) → Tasks 9, 12, 13. Internal domain from account → Tasks 12 (`domain(ofEmail:)`), 7/8 (consumed). Verification → Task 16. Decisions/ADR amend → Task 15. ✅ All spec sections map to a task.
- §6 "no schema change" — confirmed; Task 8 only fills reserved fields.

**2. Placeholder scan:** No "TBD/TODO/handle edge cases" — every code step has complete code. Task 15 Step 3 (HANDOFF prose) is descriptive by nature (free-text doc), not a code placeholder.

**3. Type consistency:** `assemble`/`AssembledContext`/`Attendee`/`match_event`/`split_sides`/`resolve_company`/`build_vocab`/`hebrew_transliteration_candidates`/`render_context_md`/`load_core_lexicon`/`correct` used consistently across Python tasks. Swift `CalendarClient.eventsURL`/`decodeEvents`/`fetchEvents`, `CalendarEvent(.When/.Attendee)`, `CalendarContext.domain(ofEmail:)`/`inputPayload`/`writeInput` consistent across Tasks 11–13. `context.input.json` / `context.vocab.json` / `context.md` filenames consistent. ✅

**Known soft spots (acceptable, by design):** transliteration is best-effort (guarded, core lexicon carries the guaranteed win); `match_event` uses `primary` calendar + timed events only (noted as follow-ups in the spec).
