# Agent Handoff — IN-meetings

<!--
Rewritten at every handoff. The incoming agent reads this + DECISIONS.md before starting.
Keep it short: last state, next steps, gotchas. History lives in git log.
-->

## Outgoing Agent
Claude Code · 2026-06-14

## Current State
**MVP Phase 1 spine + Drive sync merged; Phase 2 slice 1 (calendar context) LIVE-VERIFIED — PR open.**
- Slices **1–5 + H0/H1/H3** and **slice 6 (Drive sync, PR #5)** are merged to `main`.
- **Phase 2 slice 1 — calendar context assembler — is LIVE-VERIFIED (2026-06-14)** on branch
  `feat/phase2-calendar-context` (DECISIONS 2026-06-14, amends ADR-004). **Python 45 tests + Swift 48 tests +
  `make build-mac` green.** PR `feat/phase2-calendar-context` → `main` is open.
  - **Swift** (`Sources/INMeetingsCore/Calendar/`): `CalendarClient` + `CalendarContext` fetch candidate
    events for `[start−90m, end+30m]` and write `<meeting>/context.input.json` (with a `status` field) before
    `JobBridge` spawns the pipeline. Reuses slice-6 Google OAuth + the `calendar.events.readonly` scope.
  - **Python** (`context_assembler.py` + `data/core_lexicon.json`): match the event (max time-overlap),
    split internal/external by the signed-in account's domain, build the post-correction vocab
    (`context.vocab.json`), render `context.md` (priors + wall), merge into `metadata.json`. No schema change.
  - **Verified on a real call**: `calendar:"ok"`, attendees/company by side in `context.md`, names corrected,
    **no fabricated "Them"**. Required enabling the Calendar API first (see Gotchas).
  - **Two live-test bugs fixed + committed**: silence-gating (`asr.is_silent`) and calendar error surfacing.

## Next — START HERE
- **Merge the open PR** (`feat/phase2-calendar-context` → `main`) when ready (it now also carries the
  scope-defer + ASR-robustness work).
- **✅ VAD robustness DONE (2026-06-14):** ASR runs whisper `--vad` (Silero, app-provisioned via a second
  `ModelManager(entry:.sileroVad)` + `IN_MEETINGS_VAD_MODEL`) when present; gated so it degrades to
  `is_silent` otherwise. Validated on benchmarks (0 hallucination on the silent track; P1 proper nouns
  preserved). Committed.
- **→ NOW: app UX** — mila-like, **Liquid Glass** (macOS 26) dashboard + detail + settings + the "Record
  now" overlay, with the **menu-bar icon complementing it** (Yuval's direction 2026-06-14). This is the
  H3/H4 harvest (DECISIONS 2026-06-14 mila eval) + the [[ux-liquid-glass]] standard. **Brainstorm scope first.**
- **Saventa + Dealigence are OUT of the MVP → Phase 6** (deferred 2026-06-14): authoritative company name +
  founder priors, post-rollout. Until then `company.matched:false` (domain-derived) + best-effort
  transliteration.

## Gotchas (verified)
- **The Google Calendar API must be enabled in the OAuth client's GCP project (1062382667236).** Enabled
  2026-06-14. Symptom if ever off again: Calendar fetch 403 "API … disabled" while Drive (same token) returns
  200 and the scope is granted → surfaces as `metadata.context.sources.calendar:"error"`.
- **ivrit-whisper hallucinates Hebrew on silence** (e.g. "אדוני היושב-ראש, חבריי חברי הכנסת" — Knesset
  boilerplate). `asr.is_silent` (RMS < 1e-3) gates ASR + diarization so silent tracks (a solo call's remote
  track is digital zero) are skipped. Partial-silence within an active track is the open follow-up above.
- **New *app-target* files need `make gen`** before `make build-mac`. New **`INMeetingsCore`** files are
  picked up by SPM automatically.
- **`ASWebAuthenticationSession` in a menu-bar app**: the calendar re-consent exercised the slice-6 sign-in
  sheet successfully (2026-06-14). `AuthAnchor` falls back to a transient `NSWindow`; browser-redirect is the
  fallback if it ever fails.
- **Calendar fetch is best-effort + short-timeout (5 s) and runs before pipeline spawn** — failure writes a
  `status:"error"` (or nothing when not connected) and the pipeline degrades to unbiased. Never blocks Stop.
- (carried) pipeline tests run from `pipeline/` (or `PYTHONPATH=pipeline`); senko needs the pinned 3.11 venv;
  **TCC grant needs a relaunch**; tap write is interleaved float32 (−50 otherwise); pipeline is spawned, not
  compiled in; model download → `IN_MEETINGS_MODEL`.

## Open / follow-ups
- **Partial-silence hallucination** (above) — the most important robustness gap for real multi-party calls.
- **Phase 2 slice 1 follow-ups**: per-company variant accumulation from real ASR misses; a fuzzy/edit-distance
  post-correct pass; calendars beyond `primary`; multiple internal domains (config); title-based company fallback.
- (carried) **⚠️ PRE-ROLLOUT: single merged playback file** (DECISIONS 2026-06-14) — AVFoundation render at
  Stop → `audio.wav` / `meeting.mp4`; Drive then uploads the merged file; the dashboard (H4) plays it.
- (carried) **⏳ multi-party-call diarization quality** untested on a real 3+ call — review the per-meeting
  `pipeline.log`.
- (carried) Slice 6: retention/size cap for uploaded recordings (ADR-010); tighten Drive scope to `drive.file`.
- (carried) pyannote fallback not wired; onboarding TCC wizard minimal; Soniox fallback; ADR-010 counsel review.

## Context
- Env: macOS 26 / M3+/16GB. Local cache under `~/Library/Application Support/IN Meetings/` (`Recordings/`,
  `Models/`, `meetings.db`); Google = per-user OAuth (client id in `DriveConfig`; scopes **drive +
  calendar.events.readonly**), each user connects their own account + picks the Drive destination.
- Pipeline dev paths hardcoded in `JobBridge` (overridable via env); Phase 5 bundles the pipeline + a sealed env.
- Downstream skills call the Timeless API directly today — the context package is a NEW contract (ADR-005); the
  skills `--package` adapter (ADR-005 part 2) is Phase 3.
