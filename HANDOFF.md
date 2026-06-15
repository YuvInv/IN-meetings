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
- **P0 #1 (hybrid app shell) ✅ DONE + committed** on branch `feat/hybrid-app-shell` (not yet pushed/PR'd):
  `523bda9` (docs) + `60b3546` (code). `LSUIElement=false` (Dock icon) + `AppDelegate` (recorder stays
  alive when the dashboard closes + reopen on Dock-click) + `MenuBarLabel`; **IN Venture logo** as the
  app/Dock icon (`Assets.xcassets/AppIcon.appiconset`) + menu-bar icon (`MenuBarIcon.imageset`); source at
  `Apps/INMeetings/AppIcon-source.png`. **Verified live** (Dock + tray show the logo, close ≠ quit,
  Dock-click reopens, launch opens dashboard). Plan: `docs/superpowers/plans/2026-06-15-hybrid-app-shell.md`.
- **P0 #2 (distribution) → DEFERRED TO LAST** (final "Ship" phase, per Yuval 2026-06-15) **+ gated on an Apple Developer Program membership.** Runbook: `docs/distribution-setup.md`. Inventory (2026-06-15):
  only an `Apple Development` cert (team A6C6D257QN), **no `Developer ID Application` cert**, notarytool
  present, no stored notary creds. No Developer ID → no notarized `.dmg`; the app can't use the App Store
  (private TCC SPIs). **Launch-at-login is coupled to this** (register the *installed* `/Applications` app,
  not a DerivedData debug build) so it's parked too. Unblock = enrol in the Apple Developer Program ($99/yr;
  check if IN Venture already has an account) — walk Yuval through it. **Don't write untestable signing
  scripts before the cert exists.**

## Next — START HERE
**2026-06-15 session 2:** built **three slices on branch `feat/reliability-video-drive-picker`** (3 atomic
commits, NOT pushed/PR'd): **P0 reliability** (`56642b0`), **P1 call video** (`2ba876e`), **P1 Drive folder
picker** (`880f8cf`). All green: **Core 76 tests, pipeline 54, `make build-mac`, app launches clean.**
**⏳ The live behaviours are unverified — run `docs/manual-tests-reliability-video-picker.md` on Yuval's Mac.**
**One external blocker:** the Drive picker needs a **Google Picker browser API key** in GCP project
`1062382667236` (set `GOOGLE_PICKER_API_KEY` / `DriveConfig.pickerAPIKeyDefault`) — until then the picker
sheet shows setup steps. Then: **PR the branch** (split or single), or keep iterating.

- **P0 — trustworthy app:** (1) **hybrid app shell** ✅ DONE (`60b3546`); (2) onboarding / TCC wizard
  (Mic + System-Audio + **Screen-Recording** + Google) — **unblocked, still TODO**; (3) **reliability pass**
  ✅ CODE DONE (`56642b0`: VAD bundled+provisioned, failures surfaced) — **⏳ live-verify VAD on a real call
  + multi-party 3+ diarization.**
- **Ship (LAST):** Developer-ID sign + notarize + `.dmg` + launch-at-login + Sparkle — **deferred to the
  end** + gated on Apple Developer enrollment (runbook `docs/distribution-setup.md`).
- **P1 — value loop + video:** company-name inference + edit/rename UI ✅ (PR #9); **Claude auto-trigger →
  Saventa CRM** (one-click; `--package` mode in `~/repos/claude-skills`) — **still TODO, the main value gap**;
  **video** ✅ CODE DONE (`2ba876e`); retention cap ✅ CODE DONE (rides with video); **Drive folder picker**
  ✅ CODE DONE (`880f8cf`, real Google Picker web view) + GCP key prereq.
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
- **Partial-silence hallucination** — VAD (Silero) **now bundled in the app + provisioned-from-bundle on
  launch** (`56642b0`); still needs **live verification at scale** (record a real call, confirm no
  hallucinated Hebrew on silence). The most important robustness gap for real multi-party calls.
- **Multi-party-call (3+) diarization quality** — still untested on a real recording (P0); review the
  per-meeting `pipeline.log` once one runs.
- **Merged playback file**: ✅ audio (`audio.m4a`) + ✅ **video (`meeting.mp4`, `2ba876e`)** — muxed window
  video + balanced audio, uploaded to Drive, played in the dashboard. ⏳ live-verify A/V sync on a real call.
- **Screen Recording grant** — call video needs it; `Permissions.requestScreenRecording` provokes the prompt
  but the grant only takes effect on a **relaunch** (degrades to audio-only until then). Fold into onboarding.
- **Drive picker GCP key** — provision the **Google Picker browser API key** in project `1062382667236`
  (enable the Google Picker API) so the web-view picker renders; `GOOGLE_PICKER_API_KEY` / `pickerAPIKeyDefault`.
- **Company naming** (gap #2, P1): inference is calendar-external-domain only → "Unknown company" on no-match /
  internal-only / fetch-fail; title + transcript fallbacks designed but unused; **no edit/rename UI** yet.
- (carried) per-company variant accumulation; fuzzy/edit-distance post-correct; calendars beyond `primary`;
  multiple internal domains (config).
- (carried) retention: ✅ **prune raw tracks after Drive backup** (`2ba876e`, on by default, user-disablable);
  a **global cache-size cap** (delete oldest synced meetings beyond N GB) is still TODO. Tighten Drive scope to
  `drive.file` (P2); pyannote fallback not wired; Soniox cloud fallback; **ADR-010 counsel review — esp.
  video-on-by-default consent/retention** (now live, P1/P2).

## Context
- Env: macOS 26 / M3+/16GB. Local cache under `~/Library/Application Support/IN Meetings/` (`Recordings/`,
  `Models/`, `meetings.db`); Google = per-user OAuth (client id in `DriveConfig`; scopes **drive +
  calendar.events.readonly**), each user connects their own account + picks the Drive destination.
- Pipeline dev paths hardcoded in `JobBridge` (overridable via env); Phase 5 bundles the pipeline + a sealed env.
- Downstream skills call the Timeless API directly today — the context package is a NEW contract (ADR-005); the
  skills `--package` adapter (ADR-005 part 2) is the **P1 CRM-auto-trigger** work.
