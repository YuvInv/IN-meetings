# Agent Handoff — IN-meetings

<!--
Rewritten at every handoff. The incoming agent reads this + DECISIONS.md before starting.
Keep it short: last state, next steps, gotchas. History lives in git log.
-->

## Outgoing Agent
Claude Code · 2026-06-14

## Current State
**MVP Phase 1 spine complete + Drive sync merged + Phase 2 slice 1 (calendar context) code-complete, NOT yet live-verified.**
- Slices **1–5 + H0/H1/H3** merged + live-verified; **slice 6 (Drive sync) merged** (PR #5) — but slice 6's
  interactive Google sign-in was **never live-verified** (the `ASWebAuthenticationSession` anchor in a
  menu-bar `LSUIElement` app is the known-risky bit).
- **Phase 2 slice 1 — calendar context assembler — is code-complete on branch `feat/phase2-calendar-context`**
  (DECISIONS 2026-06-14, amends ADR-004). **Python 40 tests + Swift 48 tests + `make build-mac` all green;
  ⏳ NOT live-verified.** End to end:
  - **Swift** (`Sources/INMeetingsCore/Calendar/`): `CalendarClient` (Calendar v3 events) + `CalendarContext`
    fetch candidate events for `[start−90m, end+30m]` and write `<meeting>/context.input.json` *before*
    `JobBridge` spawns the pipeline. Reuses slice-6 Google OAuth + a new `calendar.events.readonly` scope.
  - **Python** (`pipeline/in_meetings_pipeline/context_assembler.py` + `data/core_lexicon.json`): match the
    event (max time-overlap), split internal/external by the signed-in account's domain, build the
    post-correction vocab (`context.vocab.json` — the existing `load_vocab`→`postcorrect` hook consumes it),
    render `context.md` (priors + wall), and merge `meeting.title`/`calendar_event_id`/`attendees[]`/`company`/
    `context.sources.calendar` into `metadata.json`. No schema change (slice 5 reserved every field).
  - **Guaranteed win**: the curated **core lexicon** (fund name "IN Venture" + P1 manglings) is applied on
    every meeting → `נדוויינצ'ר → IN Venture`. Per-company correction is best-effort (transliteration, partial).
    Post-correction hardened to whole-token. Degrades cleanly (no event / offline / not connected → unbiased +
    `calendar:"empty"`, never blocks transcription).
- Spec + plan: `docs/superpowers/specs/2026-06-14-phase2-calendar-context-design.md`,
  `docs/superpowers/plans/2026-06-14-phase2-calendar-context.md`.

## Next — START HERE
- **⏳ LIVE-VERIFY Phase 2 slice 1 (needs you).** Two-for-one with the slice-6 sign-in:
  1. `make run-mac` → menu **reconnect Google** (the new `calendar.events.readonly` scope forces a re-consent
     — **watch the `ASWebAuthenticationSession` sheet appear**; this is also the slice-6 sign-in live-check).
  2. Put a matching event on your `primary` calendar; record a short real call.
  3. Confirm in the meeting folder: `context.md` lists attendees by side + the company; `transcript.txt` shows
     the fund/company name corrected; `metadata.json` has `attendees[]`, `company`, `meeting.title`,
     `context.sources.calendar:"ok"`, `transcription.biased:true`.
  4. Record a short call with **no** calendar event → confirm graceful unbiased output (`calendar:"empty"`,
     `context.md` "No calendar event matched", fund-name still corrected).
  - If the sign-in sheet doesn't appear: fall back to a browser redirect (URL scheme is registered) or fix the
    `AuthAnchor` (see Gotchas).
- Then **PR** `feat/phase2-calendar-context` → `main`, and move to **Phase 2 slice 2** — Saventa
  (`sevanta_search_deals`) + Dealigence (`search-company`/`search-person`): richer vocab + authoritative
  company name + founder priors in `context.md`; sets `company.matched:true` + `sevanta_deal_id`. Same
  Swift-fetch / Python-transform shape (Swift-owned API keys in Keychain).
- **Offline check available now:** re-run the P1 eval (`pipeline/benchmarks/results/prelligence_6min_noprompt.txt`)
  through the integrated post-correct to eyeball `נדוויינצ'ר → IN Venture` before the live call.

## Gotchas (verified)
- **New *app-target* files need `make gen`** before `make build-mac` (XcodeGen only auto-regenerates on
  `project.yml` changes). New **`INMeetingsCore`** files (this slice) are picked up by SPM automatically.
- **`ASWebAuthenticationSession` in a menu-bar app** has no natural window anchor (`AuthAnchor` falls back to a
  transient `NSWindow`) — verify the sheet presents; browser-redirect is the fallback. (Now reachable via the
  Phase-2 calendar re-consent.)
- **Calendar fetch is best-effort + short-timeout (5 s) and runs before pipeline spawn** — offline/expired/no
  account simply writes no `context.input.json`, and the pipeline degrades to unbiased. It never blocks Stop.
- **@Observable + `lazy`** → mark non-observed stored props `@ObservationIgnored`. Pure helpers called from
  tests off the main actor need `nonisolated`.
- (carried) pipeline tests run from `pipeline/` (or `PYTHONPATH=pipeline`); senko needs the pinned 3.11 venv;
  **TCC grant needs a relaunch**; tap write is interleaved float32 (−50 otherwise); pipeline is spawned, not
  compiled in; model download → `IN_MEETINGS_MODEL`.

## Open / follow-ups
- **Phase 2 slice 1 follow-ups**: per-company variant accumulation from real ASR misses (grow
  `core_lexicon.json` / per-company store); a fuzzy/edit-distance post-correct pass for unseen variants (P1
  "next"); calendars beyond `primary`; multiple internal domains (config); a title-based company fallback.
- (carried) **⚠️ PRE-ROLLOUT: single merged playback file** (DECISIONS 2026-06-14) — AVFoundation render at
  Stop → `audio.wav` / `meeting.mp4`; Drive then uploads the merged file; the dashboard (H4) plays it.
- (carried) **⏳ multi-party-call diarization quality** untested on a real 3+ call (MVP-accepted) — review the
  per-meeting `pipeline.log`.
- (carried) Slice 6 follow-ups: retention/size cap for the uploaded recordings (ADR-010); tighten the Drive
  scope to `drive.file` if per-user ownership changes.
- (carried) pyannote fallback not wired; onboarding TCC wizard minimal; Soniox fallback; ADR-010 counsel review.

## Context
- Env: macOS 26 / M3+/16GB. Local cache under `~/Library/Application Support/IN Meetings/` (`Recordings/`,
  `Models/`, `meetings.db`); Google = per-user OAuth (client id in `DriveConfig`; scopes now **drive +
  calendar.events.readonly**), each user connects their own account + picks the Drive destination.
- Pipeline dev paths hardcoded in `JobBridge` (overridable via env); Phase 5 bundles the pipeline + a sealed env.
- Downstream skills call the Timeless API directly today — the context package is a NEW contract (ADR-005); the
  skills `--package` adapter (ADR-005 part 2) is Phase 3.
