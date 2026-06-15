# ADR-004 — Pre-transcription context assembler (the differentiator)

> **⚠️ Also amended 2026-06-15** (see [DECISIONS.md](../DECISIONS.md)): **Saventa + Dealigence enrichment is deferred to Phase 6** — the live MVP/P1 context layer is **Google Calendar only** (domain-derived company, `matched:false`). Company-name *inference fallback + an edit/rename UI* are **P1**.

**Status:** Proposed · **Date:** 2026-06-11 · **Deciders:** Yuval (review)
**Brief item:** C · **Research:** RESEARCH.md §3.4 (biasing), §0 (strategic bet)

> **Amended 2026-06-14 (Phase 2 slice 1, calendar-first):** mechanism = deterministic post-correction
> (not `initial_prompt`); runtime = **Swift fetch / Python transform** (not "the pipeline calls MCP
> servers" — a headless subprocess can't reach MCP); calendar-first (Saventa/Dealigence = slice 2); the
> internal/external split is derived from the signed-in account's domain. See `DECISIONS.md` 2026-06-14
> and `docs/superpowers/specs/2026-06-14-phase2-calendar-context-design.md`.

## Context

This is the core differentiator: feed the ASR what it needs to get Hebrew proper nouns and code-switched
English terms right, *before* transcription, and emit a `context.md` for the Claude skills. The
available sources (all already connected as MCPs / skills) are Google Calendar, Saventa/MyDealFlow CRM,
and Dealigence. The research caveat: prompt biasing only honors ~224 tokens and is soft — so the
vocabulary must be **ranked and tight**, not a data dump.

## Decision

When a meeting is detected (ADR-001), run the assembler **in parallel with capture** so the vocabulary
is ready by the time transcription starts.

**Pipeline:**
1. **Match the meeting to a Calendar event.** Search ±90 min around now; match by active meeting URL
   (best), then by attendee/title. From the event take: title, **organizer** (their domain = the IN
   Venture internal domain — used to split internal vs external attendees), **attendees (names +
   emails)**, description, linked docs, recurrence.
2. **Identify the company.** From the event title / external attendee email domains, resolve a company
   name. Look it up in **Saventa** (`sevanta_search_deals`) → deal id, stage, prior notes/summaries;
   and in **Dealigence** (`search-company` / `search-person`) → founder backgrounds, prior companies,
   investors for the people on the call.
3. **Emit two artifacts:**
   - **Correction vocabulary** (`vocab.json`, internal) — **per entity: a canonical spelling + a list
     of variant spellings** (Hebrew + Latin), e.g. `{"canonical": "IN Venture", "variants":
     ["נדוויינצ'ר", "אינוונצ'ר", ...]}`. **[Amended by P1]** This feeds **deterministic post-correction**
     of the ASR output (ADR-003), NOT an `initial_prompt` — P1 proved prompt biasing fails (Latin terms
     regress names). Sources for variants: CRM/Dealigence canonical names + a transliteration generator;
     grow the observed-variant list from real misses. (An optional, short, Latin-free Hebrew domain
     primer may still be passed as `initial_prompt`, but it is not the mechanism.)
   - **`context.md`** (in the package) — human/Claude-readable priors: who's on the call (names, roles,
     emails, side), the company one-liner + stage from Saventa, founder backgrounds from Dealigence,
     links to prior meeting summaries. **Clearly marked as PRIORS, not as meeting content** — the
     downstream skills (esp. `saventa-summary`) enforce a wall: deal narrative comes only from the
     call, calendar/CRM is identity/logistics only. The header of `context.md` states this explicitly.

**Graceful degradation (must be first-class, not an afterthought):**
- **No calendar match** → fall back to meeting-app/title heuristics for a company guess; vocabulary
  from whatever external attendees/URL we have; `context.md` notes "no calendar event matched". Never
  block recording or transcription.
- **No CRM/Dealigence match** (new company we've never met) → `context.md` says "no prior record"; the
  vocabulary is just the calendar attendee names; flag the meeting in metadata as `company_matched:
  false` so the dashboard can prompt the user to link it later.
- **Partial match** → use what resolves; record per-source success in `metadata.json`
  (`context.sources: {calendar, saventa, dealigence}` each ok/empty/error).

**Where it runs:** the assembler is part of the Python pipeline (ADR-009) and calls the same MCP
servers the user already has connected. Auth reuses the existing MCP configuration; no new credentials.

## Options considered

| Option | Why not |
|--------|---------|
| Dump all CRM/Dealigence text into the prompt | Only ~224 tokens are honored; noise crowds out the high-value names. Ranking is required. |
| Assemble context *after* transcription | Defeats the entire premise — biasing must precede ASR. (Post-hoc enrichment still happens via the Claude skills, but that's additive.) |
| Skip biasing, rely on post-correction only | Loses the strategic edge; post-correction is the *fallback* if prompt biasing underperforms (ADR-003), not the plan. |
| Require a calendar match | Brittle; many calls are ad-hoc. Degradation must be graceful. |

## Consequences

- **Good:** directly serves the strategic bet; reuses existing MCP connections; produces both the ASR
  vocabulary and the Claude-facing `context.md` from one pass; the internal/external split it computes
  is exactly what `saventa-summary` needs for email filtering.
- **Costs/risks:** MCP calls add latency (mitigated by running parallel with capture, which lasts the
  whole meeting); company-name resolution from a title/domain is fuzzy (record confidence, let the user
  correct in the dashboard); mixed-script name biasing is unproven (Prototype 1). The wall between
  priors and meeting content must be respected by the skills — enforced by clear labeling in
  `context.md` and reaffirmed in ADR-005.
