# Agent Handoff — IN-meetings

<!--
Rewritten at every handoff. The incoming agent reads this + DECISIONS.md before starting.
Keep it short: last state, next steps, gotchas. History lives in git log.
-->

## Outgoing Agent
Claude Code · 2026-06-15

## Current State
**MVP spine is complete and merged to `main` (App UX slice 1 = PR #7, `46e5fe9`); local `main` synced.**
The app runs the full chain end-to-end: detect a call → dual-track capture → on-device Hebrew
transcription (post-correction + Silero VAD) → senko diarization → frozen-schema context package +
SQLite index → per-user Google Drive backup → Liquid Glass dashboard (browse / play merged `audio.m4a`
/ read RTL transcript) + tabbed Settings (Recording / Model / Drive).
- Phase 0 (P1 ASR, P2 capture, P3 detection) + Phase 1 MVP + Phase 2 calendar context + App UX slice 1
  are all on `main`. PR #7 also carried the VAD + Phase-6-scope-defer commits `main` had been missing.
- **2026-06-15: full gap analysis + re-prioritization done this session** — see `IMPLEMENTATION_PLAN.md`
  → **"Road to a team-ready v1"** and `DECISIONS.md` (2026-06-15: two entries — the priority order, and
  the hybrid Dock + menu-bar app-shell decision).
- **P0 #1 (hybrid app shell) IN PROGRESS** on branch `feat/hybrid-app-shell` — `LSUIElement=false` (Dock
  icon) + a new `AppDelegate` (keep the recorder alive when the dashboard closes + reopen on Dock click) +
  a `MenuBarLabel`, all in `INMeetingsApp.swift`. `make build-mac` green; ⏳ **pending live-verify** (Dock
  icon appears, close ≠ quit, Dock-click reopens) before the commit. Plan:
  `docs/superpowers/plans/2026-06-15-hybrid-app-shell.md`.

## Next — START HERE
Work the ordered roadmap in `IMPLEMENTATION_PLAN.md` → "Road to a team-ready v1". **Sequencing
(Yuval, 2026-06-15): video is pulled up into P1.** The brainstorm/gap-analysis is done; per the
brainstorming flow the next step is to write an implementation plan (writing-plans skill) for the
first P0 item, then **build + verify each item on a real meeting before the next**.

- **P0 — installable & trustworthy:** (1) **hybrid app shell** — Dock icon + menu-bar tray
  (`LSUIElement=false` + keep `MenuBarExtra`; don't quit on dashboard close; quiet login) — cheap,
  high-impact, **start here**; (2) Developer-ID sign + notarize + `.dmg` + launch-at-login; (3)
  onboarding / TCC wizard (Mic + System-Audio + Google); (4) reliability pass — bundle VAD, verify a
  real 3+ call, surface pipeline failures.
- **P1 — value loop + video:** company-name inference + **edit/rename UI**; **Claude auto-trigger →
  Saventa CRM** (one-click; `--package` mode in `~/repos/claude-skills`); **video** capture →
  `meeting.mp4` → Drive → playback; retention/size cap (rides with video); Drive folder picker.
- **P2 — polish:** ring-buffer, auto-stop prompt, speaker naming, trash/export, settings depth.
- **Out of scope for v1:** the in-app "AI overview" panel (the CRM *trigger* is in P1; the rich summary
  surface is deferred).

## Gotchas (verified)
- **The Google Calendar API must be enabled in the OAuth client's GCP project (1062382667236).** Enabled
  2026-06-14. Symptom if ever off again: Calendar fetch 403 "API … disabled" while Drive (same token) returns
  200 and the scope is granted → surfaces as `metadata.context.sources.calendar:"error"`.
- **ivrit-whisper hallucinates Hebrew on silence** (e.g. "אדוני היושב-ראש, חבריי חברי הכנסת" — Knesset
  boilerplate). `asr.is_silent` (RMS < 1e-3) gates ASR + diarization so silent tracks (a solo call's remote
  track is digital zero) are skipped; whisper.cpp `--vad` (Silero) handles silence *within* an active track
  when the VAD model is present. Bundling VAD in the app + a live partial-silence check is a P0 item.
- **New *app-target* files need `make gen`** before `make build-mac`. New **`INMeetingsCore`** files are
  picked up by SPM automatically.
- **`ASWebAuthenticationSession` in a menu-bar app**: the calendar re-consent exercised the slice-6 sign-in
  sheet successfully (2026-06-14). `AuthAnchor` falls back to a transient `NSWindow`; browser-redirect is the
  fallback if it ever fails. (Watch this when the app shell flips to `LSUIElement=false` in P0.)
- **Calendar fetch is best-effort + short-timeout (5 s) and runs before pipeline spawn** — failure writes a
  `status:"error"` (or nothing when not connected) and the pipeline degrades to unbiased. Never blocks Stop.
- (carried) pipeline tests run from `pipeline/` (or `PYTHONPATH=pipeline`); senko needs the pinned 3.11 venv;
  **TCC grant needs a relaunch**; tap write is interleaved float32 (−50 otherwise); pipeline is spawned, not
  compiled in; model download → `IN_MEETINGS_MODEL`.

## Open / follow-ups
- **Partial-silence hallucination** — VAD (Silero) added + validated in benchmarks; still needs **bundling in
  the app + live verification at scale** (P0 reliability pass). The most important robustness gap for real
  multi-party calls.
- **Multi-party-call (3+) diarization quality** — still untested on a real recording (P0); review the
  per-meeting `pipeline.log` once one runs.
- **Merged playback file**: ✅ audio (`audio.m4a`, slice 1, uploaded to Drive). ⏳ `meeting.mp4` (video) lands
  with the P1 video work.
- **Company naming** (gap #2, P1): inference is calendar-external-domain only → "Unknown company" on no-match /
  internal-only / fetch-fail; title + transcript fallbacks designed but unused; **no edit/rename UI** yet.
- (carried) per-company variant accumulation; fuzzy/edit-distance post-correct; calendars beyond `primary`;
  multiple internal domains (config).
- (carried) retention/size cap (ADR-010, P1); tighten Drive scope to `drive.file` (P2); pyannote fallback not
  wired; Soniox cloud fallback; **ADR-010 counsel review — esp. video-on-by-default consent/retention** (P1/P2).

## Context
- Env: macOS 26 / M3+/16GB. Local cache under `~/Library/Application Support/IN Meetings/` (`Recordings/`,
  `Models/`, `meetings.db`); Google = per-user OAuth (client id in `DriveConfig`; scopes **drive +
  calendar.events.readonly**), each user connects their own account + picks the Drive destination.
- Pipeline dev paths hardcoded in `JobBridge` (overridable via env); Phase 5 bundles the pipeline + a sealed env.
- Downstream skills call the Timeless API directly today — the context package is a NEW contract (ADR-005); the
  skills `--package` adapter (ADR-005 part 2) is the **P1 CRM-auto-trigger** work.
