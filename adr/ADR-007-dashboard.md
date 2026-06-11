# ADR-007 — Dashboard

**Status:** Proposed · **Date:** 2026-06-11 · **Deciders:** Yuval (review)
**Brief item:** E (dashboard) · **Aesthetic:** clean, minimal, no clutter

## Context

We need a simple "past meetings" view: list, search, open transcript, play media, jump to the Drive
files, re-run a Claude skill. The brief says recommend the lightest stack that's still pleasant — a
small SwiftUI window or a tiny local web app over SQLite. Nothing heavy.

## Decision

**A SwiftUI window inside the same menu-bar app**, reading the SQLite store (ADR-006).

Rationale: the app is already Swift/SwiftUI (ADR-009); a native window means **zero extra runtime,
process, or port**, native media playback (`AVKit`), Keychain access for the Drive links, and one
codebase. A local web app would add a server, a browser tab, and a second UI stack for no benefit at
this scale.

**Views (minimal):**
- **List** — reverse-chronological meetings: company, title, date, duration, status chips
  (transcribed / synced / summarized), a "new company — link?" flag when `company.matched == false`.
- **Search** — full-text over transcript.txt + metadata (SQLite FTS5). Company/date filters.
- **Detail** — transcript (speaker-named, click a line to seek), inline player for mic/system tracks
  (and video if present), `context.md` and `slides_ocr.md` rendered, attendee list.
- **Actions** — Open in Drive (deep link); Re-run a skill (saventa-summary / generate-mom /
  process-meeting / enrich-company) on this package via ADR-008; Re-transcribe (full model, or opt-in
  cloud); Edit company/attendee mapping (fixes a fuzzy match, updates metadata + re-links); Delete
  (per-meeting purge — ADR-010).

**Aesthetic:** standard SwiftUI, system materials, generous whitespace, no chrome. Matches the user's
"clean, minimal" preference and the menu-bar app's restraint.

## Options considered

| Option | Why not |
|--------|---------|
| Tiny local web app (Flask/FastAPI + htmx) over SQLite | Adds a server process + port + browser dependency + a second UI stack; native gives media playback and Drive/Keychain for free. |
| Electron/Tauri dashboard | Heavy; defeats "native, minimal". |
| No dashboard (menu-bar list only) | Insufficient for search/playback/re-run; the brief explicitly wants a past-meetings view. |

## Consequences

- **Good:** one app, one language, native playback and deep links, no extra runtime; FTS5 search is
  trivial and fast at this scale.
- **Costs/risks:** SwiftUI media + transcript-seek UI is some work (but standard `AVKit`); the
  dashboard reads state the Python pipeline writes, so the SQLite schema is a shared interface (ADR-009
  defines who writes what). If a web view is ever wanted for remote access, the SQLite store keeps that
  option open later.
