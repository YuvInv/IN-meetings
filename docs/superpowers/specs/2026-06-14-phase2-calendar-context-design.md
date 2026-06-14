# Phase 2 · Slice 1 — Calendar context assembler

**Date:** 2026-06-14 · **Author:** Claude Code (design by Yuval) · **Status:** Approved (design), pending spec review
**Amends:** ADR-004 (context assembler) · **Reuses:** slice-5 job hand-off, slice-6 Google OAuth
**Phase:** 2 (the differentiator — context injection), first sub-slice

---

## 1. Why / background

The core differentiator is feeding the recorder per-meeting context so Hebrew + code-switched English
proper nouns come out right, and emitting a `context.md` of priors for the downstream Claude skills
(ADR-004). Phase 2 builds the **context assembler**. This is its first, thinnest vertical: **Google
Calendar only** (Saventa + Dealigence are slice 2).

Two facts reshape ADR-004 as originally written, and this slice is designed around them:

1. **The vocabulary is consumed *after* ASR, not before.** ADR-004 said "run parallel with capture so the
   vocab is ready before transcription" — that was premised on `initial_prompt` biasing, which **P1
   disproved** (Latin-script prompts *regress* names; see `pipeline/benchmarks/P1-FINDINGS.md`). The real
   mechanism is **deterministic post-correction** of the ASR output (`postcorrect.py`), which runs
   post-transcription. The hook already exists: `__main__.py:load_vocab()` reads `context.vocab.json` and
   post-correction is a no-op until that file appears. So the assembler is just a pipeline step that must
   finish before the post-correct line — a far weaker timing constraint than "before ASR".

2. **The headless pipeline cannot call MCP servers.** ADR-004 said "the assembler is part of the Python
   pipeline and calls the same MCP servers the user already has connected." But the pipeline is a **headless
   subprocess** (`JobBridge` spawns `pipeline/.venv/bin/python`); MCP servers are bound to an interactive
   Claude session, not to an arbitrary subprocess. And slice 6 changed the landscape: **Swift now owns Google
   OAuth** (token in Keychain, `DriveTokenManager` refresh). So credentialed fetch belongs in Swift; the
   pipeline receives already-fetched data.

## 2. Goal & non-goals

**Goal:** When a meeting finishes, match it to its Google Calendar event, derive attendees (+ internal/
external side) and the company, use that to (a) correct company/fund names in the Hebrew transcript via the
existing post-correction path and (b) write `context.md` priors and fill the reserved `metadata.json`
fields. Degrade gracefully (never block transcription) when there's no match.

**Non-goals (explicitly deferred):**
- Saventa deal lookup + Dealigence founder backgrounds → **slice 2**.
- Learning/growing variant spellings from real ASR misses → later refinement (the store is shaped to allow it).
- Live in-call UI of the matched meeting (the match is computed at Stop, headless) → later (dashboard / overlay).
- Correcting attendee **personal** names in the transcript (false-replacement risk) → priors-only in this slice.
- Any `metadata.schema.json` change — **slice 5 already reserved every field used here** (verified).

**Done when:** transcripts measurably improve on company/fund names vs Phase-1 unbiased — on the P1 eval
audio and on a live call — and a real meeting yields a correct `context.md` + populated `metadata.json`,
with graceful degradation confirmed on a no-calendar-match call.

## 3. Behavior (what the user gets)

For one recorded call, on Stop, with no extra clicks:
1. The app reads the user's Google Calendar around the meeting window and picks the matching event.
2. From it: title, attendees (names + emails), and the company (from external attendees' email domains).
3. The transcript gets a correction pass — e.g. the fund name **"IN Venture"** (mangled *every time* per P1)
   and the meeting's company name are rewritten to canonical spelling:
   `…אז אנחנו נדוויינצ'ר…` → `…אז אנחנו IN Venture…`
4. The package gains `context.md` (priors, clearly walled off from meeting content) and `metadata.json` is
   filled in (`meeting.title`, `attendees[]` with side, `company{matched:false}`, `transcription.biased:true`).

When it can't match (no event found / offline / Google sign-in expired): the transcript is produced exactly
as today (unbiased), `context.md` records "no calendar event matched", and `metadata.context.sources.calendar
= "empty"`. **Transcription is never blocked.**

## 4. Architecture — Swift fetches, Python matches + transforms

Chosen split (consistent with slices 5–6: secrets stay in Swift; Python is the single writer of the package;
all transcript/text logic + fixture tests live in Python next to `postcorrect.py`/`metadata.py`):

```
 ┌─────────────────────────── Swift (app) ───────────────────────────┐
 │ slice-6 Google OAuth  +  NEW scope: calendar.events.readonly       │
 │ On Stop, when assembling the job:                                   │
 │   CalendarClient.fetchCandidates(window) ──auth via DriveTokenMgr── │
 │     GET calendar/v3/calendars/primary/events?timeMin&timeMax        │
 │   write  <meeting>/context.input.json   { candidates, hints }       │
 └───────────────────────────────┬───────────────────────────────────┘
                                  │ file hand-off (like slice-5 job.json facts)
 ┌───────────────────────────────▼─── Python (pipeline) ─────────────┐
 │ context_assembler.assemble(dir, internal_domain):                  │
 │   read context.input.json (absent → degrade, no-op)                │
 │   match_event(candidates, hints)      → event | None               │
 │   split_sides(event, internal_domain) → internal/external          │
 │   resolve_company(event)              → {name, matched:false}      │
 │   build_vocab(company, core_lexicon)  → write context.vocab.json   │
 │   render_context_md(...)              → write context.md           │
 │   return assembled-context (for metadata merge)                    │
 │ ── then the EXISTING flow runs unchanged: ──                       │
 │   load_vocab() picks up context.vocab.json → post-correct segments │
 │   build_metadata(..., context) fills attendees/company/sources     │
 └────────────────────────────────────────────────────────────────────┘
```

**Internal domain** is derived from the **signed-in Google account's email domain** (`DriveClient.accountEmail`
→ `in-venture.com`), passed in `context.input.json`. No hardcoding; auto-correct per user. (Multiple internal
domains = a later config item.)

## 5. Components

### 5.1 Swift (app target — needs `make gen` for new files)
- **Scope addition:** add `https://www.googleapis.com/auth/calendar.events.readonly` to the OAuth scope set
  in `GoogleOAuth`/`DriveConfig`. *Consequence:* already-connected users must re-consent (incremental auth) —
  this re-consent is a natural moment to also live-verify the still-unverified slice-6 sign-in.
- **`CalendarClient`** (`Sources/INMeetingsCore/Drive/` or a new `Calendar/` dir): one method,
  `fetchCandidates(timeMin:timeMax:)`, a `GET` to the Calendar v3 events endpoint on `primary`, with
  `singleEvents=true&orderBy=startTime`, authorized via the existing `DriveTokenManager` access token. Returns
  decoded candidate events (id, summary, start/end, attendees[email,displayName,organizer,self], hangoutLink/
  conferenceData). Mirrors `DriveClient`'s URLSession + auth pattern. **Fail-soft:** timeout/offline/auth-error
  → return empty, never throw into Stop.
- **Job assembly hook:** at Stop, *before spawning the pipeline*, fetch candidates for the window
  `[started_at − 90m, ended_at + 30m]` (a short ~5s timeout — the pipeline then runs for minutes, so this
  is negligible) and write `<meeting>/context.input.json` alongside `job.json`:
  `{ "internal_domain": "<account-domain>", "hints": { "capture_source_app": "...", "started_at": "...",
  "ended_at": "..." }, "candidates": [ <trimmed events> ] }`. On timeout/failure, write **no** file ⇒
  pipeline degrades cleanly. The file always precedes pipeline spawn, so the assembler never races it.
- **Unit tests:** request-building (URL, query params, auth header), candidate trimming, `context.input.json`
  shape. (Live OAuth re-consent is a manual check.)

### 5.2 Python (pipeline)
New module `in_meetings_pipeline/context_assembler.py` + data file `data/core_lexicon.json`:
- **`match_event(candidates, hints)`** — pick the candidate whose `[start,end]` has the **greatest overlap**
  with the recording window `[started_at, ended_at]`; require overlap **> 0** (no overlap ⇒ no match);
  tie-break toward events that have external attendees and/or a conferencing link. Return the event or `None`.
  (Active-meeting-URL matching is *not* available — the P3 detector identifies the app by bundle id, not the
  URL — so matching is time + attendees + link only.)
- **`split_sides(event, internal_domain)`** — attendee email domain `== internal_domain` ⇒ `internal`, else
  `external`; include the organizer. Returns the attendee list with `side`.
- **`resolve_company(event, externals)`** — company name from the dominant external email domain
  (strip TLD, split on `.`/`-`, title-case), falling back to a parse of the event title. `matched:false`
  (no CRM confirmation in this slice).
- **`build_vocab(company, core_lexicon)`** — emit `context.vocab.json` in the format `postcorrect.py` already
  consumes (`[{canonical, variants[]}]`): the **curated core lexicon** (the fund name "IN Venture" + its known
  manglings from P1; always applied — this is the *proven* win, since P1 showed the worst manglings aren't
  clean transliterations) **plus** one best-effort entry for the meeting's company `{canonical: <name>,
  variants: [<Latin literal>, <rule-based Hebrew transliteration candidates>]}`. Per-company coverage is
  expected to be partial in this slice and improves as variants accumulate (deferred follow-up).
  **Conservative:** whole-token replacement only (existing `correct()`), scoped to this meeting's entities —
  no global lists, no personal names.
- **`render_context_md(event, attendees, company)`** — write `context.md` with a mandatory wall header
  (priors only, identity/logistics, *not* meeting content — the rule `saventa-summary` enforces), then
  Meeting/Source, Attendees grouped by side, Company.
- **`assemble(directory, internal_domain)`** — orchestrates the above; returns an in-memory context object for
  the metadata merge; on any failure or missing input, returns an "empty" context (degradation), writes a
  `context.md` noting no match, and writes no vocab (post-correction stays a no-op).
- **`__main__.run()` wiring** — call `assemble()` early in `run()` (before transcription; it's independent of
  ASR). The existing `load_vocab()` → post-correct path then picks up `context.vocab.json` unchanged.
- **`metadata.build_metadata(...)`** gains a `context=` parameter and fills: `meeting.title`,
  `meeting.calendar_event_id`, `attendees[]`, `company`, and `context.sources.calendar` ∈ {ok, empty, error}.
  `transcription.biased`/`vocabulary_terms_used` already flow from the vocab (unchanged).
- **Tests** (`tests/test_context.py` + extend `test_metadata.py`/`test_contract.py`): match (overlap / no
  match / multiple candidates), side split, company resolution (domain + title fallback), vocab assembly
  (core + company), `context.md` rendering incl. the wall header, metadata population, and **degradation**
  (no `context.input.json` ⇒ no-op, `biased:false`, `calendar:"empty"`).

## 6. Data & file contracts
- **Input** `<meeting>/context.input.json` (Swift → Python): `{ internal_domain, hints{capture_source_app,
  started_at, ended_at}, candidates[] }`.
- **Outputs** (Python, in the package): `context.vocab.json` (internal; consumed by post-correction),
  `context.md` (in the package), and the merged fields in `metadata.json` (§5.2). `transcript.json/.txt`
  reflect the corrected text. No new schema version — all fields pre-reserved (§ metadata.schema.json).
- **Core lexicon** `in_meetings_pipeline/data/core_lexicon.json`: small, checked-in `[{canonical, variants[]}]`,
  seeded from P1's observed manglings (e.g. `IN Venture` ← `נדוויינצ'ר`, `אינוונצ'ר`, …).

## 7. `context.md` format (the priors wall)
```
# Meeting context — PRIORS ONLY
> Identity & logistics assembled from the calendar. NOT meeting content.
> Deal narrative, decisions, and quotes must come ONLY from the transcript.

**Meeting:** <title> · <ISO start>–<end>
**Source:** Google Calendar (event <id>)

## Attendees
### IN Venture (internal)
- <name> <email>
### <Company> (external)
- <name> <email>

## Company
- **<name>** — inferred from <domain>. Not yet linked to a CRM deal (matched: false).
```
On no match: a one-line `context.md` stating "No calendar event matched; priors unavailable."

## 8. Degradation matrix
| Situation | Behavior |
|---|---|
| No `context.input.json` (no Calendar scope / Swift fetch failed) | Python no-op; transcript unbiased; `calendar:"empty"`; `context.md` notes no priors. |
| Candidates present, none overlap | `match_event → None`; same as above but `calendar:"empty"`. |
| Event matched, no external attendees | attendees populated; `company:null`/`matched:false`; vocab = core lexicon only. |
| Assembler raises | caught; `calendar:"error"`; transcription proceeds unbiased. |

Transcription/diarization are **never** gated on the assembler.

## 9. Verification (per the verify-each-slice rule)
1. **Python fixture tests** — all of §5.2, incl. degradation. `ruff` clean.
2. **P1 eval re-run** — run the integrated pipeline over the P1 audio with the curated vocab; show
   unbiased-vs-corrected replacements (re-confirms the P1 result through the real path).
3. **Swift** — `swift test` (CalendarClient request-building) + `make build-mac` green.
4. **Live** — (a) a real call *with* a calendar event → confirm matched attendees/company in `context.md`,
   corrected names in `transcript.txt`, `biased:true`, populated metadata; (b) a call with *no* event →
   confirm graceful unbiased output. (Exercises the slice-6 sign-in via the new calendar re-consent.)

## 10. Decisions to record (DECISIONS.md — amends ADR-004)
- Context-injection mechanism = deterministic post-correction (reaffirm P1's amendment).
- Assembler runtime split: **Swift credentialed fetch (Google OAuth + `calendar.events.readonly`) / Python
  match + transform**. Supersedes ADR-004's "Python pipeline calls MCP servers" (not viable headless) and
  relaxes "run parallel with capture" (now a post-ASR step).
- **Calendar-first** sub-slice; Saventa + Dealigence deferred to slice 2.
- Internal domain derived from the signed-in Google account; conservative vocab (company + curated core,
  personal names excluded from the rewrite).

## 11. Open follow-ups
- Slice 2: Saventa (`sevanta_search_deals`) + Dealigence (`search-company`/`search-person`) → richer vocab +
  authoritative canonical company name + founder priors in `context.md`; sets `company.matched:true` +
  `sevanta_deal_id`/`dealigence_id`. (Credential path: Swift-owned API keys in Keychain, same fetch→handoff shape.)
- Variant learning from real misses (grow `core_lexicon.json` / per-company store).
- Multiple internal domains (config).
- Calendars beyond `primary`.
- A fuzzy/edit-distance post-correction pass for unseen variants (guard short tokens) — P1 "next".
```
