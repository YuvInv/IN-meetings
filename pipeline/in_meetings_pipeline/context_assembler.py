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
import sys
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

_DATA = Path(__file__).parent / "data"

# Public email providers are never a company identity.
_PUBLIC_DOMAINS = {"gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "yahoo.com", "icloud.com"}

# Best-effort Latin→Hebrew phonetic map (single most-common rendering per letter). Deliberately small;
# real coverage comes from the curated lexicon now and accumulated observed variants later (deferred).
_TRANSLIT = {
    "a": "א", "b": "ב", "c": "ק", "d": "ד", "e": "", "f": "פ", "g": "ג", "h": "ה", "i": "י",
    "j": "ג'", "k": "ק", "l": "ל", "m": "מ", "n": "נ", "o": "ו", "p": "פ", "q": "ק", "r": "ר",
    "s": "ס", "t": "ט", "u": "ו", "v": "ו", "w": "ו", "x": "קס", "y": "י", "z": "ז",
}

_WALL = (
    "# Meeting context — PRIORS ONLY\n"
    "> Identity & logistics assembled from the calendar. NOT meeting content.\n"
    "> Deal narrative, decisions, and quotes must come ONLY from the transcript.\n"
)


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


# --- event matching ---------------------------------------------------------

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
    Tie-break toward events with a conferencing link, then larger attendee lists."""
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


# --- attendees + company ----------------------------------------------------

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
    """Company = the dominant non-public external email domain; else None. matched:false (no CRM here).

    `title` is accepted for a future title-based fallback (slice 2); unused while domain resolution wins.
    """
    domains = [d for a in attendees if a.side == "external"
               if (d := _domain(a.email)) and d not in _PUBLIC_DOMAINS]
    if not domains:
        return None
    dominant = Counter(domains).most_common(1)[0][0]
    return {"name": _company_name_from_domain(dominant),
            "sevanta_deal_id": None, "dealigence_id": None, "matched": False}


# --- vocabulary -------------------------------------------------------------

def hebrew_transliteration_candidates(latin: str) -> list[str]:
    """One best-effort Hebrew spelling of a Latin word, guarded to >=4 chars (shorter is too risky)."""
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


# --- context.md -------------------------------------------------------------

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


# --- orchestration ----------------------------------------------------------

def assemble(directory: Path) -> AssembledContext:
    """Orchestrate the calendar-first assembler. Always writes context.vocab.json (>= core lexicon) and
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
