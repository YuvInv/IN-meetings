# Agent Handoff — IN-meetings

<!--
Rewritten at every handoff. The incoming agent reads this + DECISIONS.md before starting.
Keep it short: last state, next steps, gotchas. History lives in git log.
-->

## Outgoing Agent
Claude Code · 2026-06-22 (session 6)

## Current State
**Road-to-v1 nearly complete; `main` is at the PR #14 merge.** End-to-end: detect → dual-track capture →
on-device Hebrew transcription (post-correction + Silero VAD) → senko diarization → frozen-schema context
package + SQLite index → per-user Drive backup → Liquid Glass dashboard (browse / play `meeting.mp4`/`audio.m4a`
/ read RTL transcript) + tabbed Settings + a first-run onboarding wizard.

**Merged to `main` this session (2026-06-22):**
- **[PR #12] saventa-summary auto-trigger** — call done → headless `claude -p` + app-bundled recipe →
  `summary.md` → dashboard Summary panel + Drive. **Sevanta/CRM posting ON HOLD.**
- **[PR #13] auto-stop on meeting end** — debounced visible countdown on the detector's **armed→idle** edge
  (`AutoStopArbiter` + `MeetingEndCoordinator`/`Overlay`; `autoStopEnabled` default on; amends ADR-002,
  supersedes the 2026-06-14 keep-if-ignored choice).
- **[PR #14] onboarding/TCC wizard (live-verified)** — 3-step **Mic → Screen & System Audio Recording →
  Google**; single-primary grant button + "Skip for now"; auto-opens first run, re-runnable from the menu.
  Plus **model visibility + management** (wizard download status; Settings → Models path/size/Reveal/Delete/
  Re-download) **and folded-in local test tooling** (`make dmg`, `make reset-test-data`).

**Load-bearing finding (DECISIONS 2026-06-22):** macOS 15/26 has **no separate "System Audio Recording"
grant** — system audio is covered by **"Screen & System Audio Recording"** (confirmed empirically: the
Core-Audio-tap "Them" track records with only Screen Recording granted). So onboarding is 3 steps.

Earlier on `main`: hybrid app shell (PR #8), company naming (#9), reliability/VAD + call video + Drive picker
(#10/#11), A/V-sync rewrite + ~6× smaller files + speaker naming (#11).

## Next — START HERE

**Two features captured for THIS session — design briefs written; brainstorm → spec → build:**
1. **Calendar-driven audio upload + context** (reshapes the old "audio-file upload" must-have). A **right-side
   calendar panel** on the dashboard (after Google connect) → click a meeting → **upload an audio file + assign
   it to that meeting** → the event's context (time/attendees/company) enriches the package and gives candidate
   identities for the diarized speakers. **Reality to align on:** an uploaded file is a single mixed track;
   diarization separates speakers but true voice-ID auto-naming is a **separate project** — v1 = assisted
   labelling from the attendee list. Reuses `CalendarClient`/`CalendarContext` + the synthetic-`job.json`
   import path + `SpeakerEditor`. **Brief: `docs/superpowers/specs/2026-06-22-calendar-upload-context-brief.md`.**
2. **Modular / resizable meeting layout** (after #1). Make `MeetingDetailView`'s **video / summary / transcript**
   panes resizable (today a fixed `VStack`; likely `HSplitView`/`VSplitView` + persisted sizes, adapting when
   there's no video). **Brief: `docs/superpowers/specs/2026-06-22-modular-meeting-layout-brief.md`.**

**Other remaining v1 gaps:** **Ship** phase (Developer-ID sign + notarize + `.dmg` + launch-at-login + Sparkle
— done LAST, gated on a **$99 Apple Developer account**; runbook `docs/distribution-setup.md`; interim
**`make dmg`** exists for local unsigned install testing); a **global cache-size cap**. The in-app "AI overview"
panel stays out of v1.

**Live-test debt (needs Yuval at the GUI on a real call):** **auto-stop** (#13 — countdown + cancel paths,
`docs/manual-tests-auto-stop.md`); **saventa-summary** panel + full flow (#12,
`docs/manual-tests-saventa-summary.md`); partial-silence VAD + multi-party (3+) diarization.

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
- **Screen Recording grant** — call video + the system-audio tap need it; the grant only takes effect on a
  **relaunch** (degrades until then). ✅ folded into the onboarding wizard (PR #14) with a restart-at-the-end.
- **Drive picker GCP key** — provision the **Google Picker browser API key** in project `1062382667236`
  (enable the Google Picker API) so the web-view picker renders; `GOOGLE_PICKER_API_KEY` / `pickerAPIKeyDefault`.
- **Company naming** (gap #2, P1): edit/rename UI ✅ (PR #9). Inference is still calendar-external-domain only
  → "Unknown company" on no-match / internal-only / fetch-fail; title + transcript fallbacks designed but unused.
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
- Downstream skills called the Timeless API directly — the context package is a NEW contract (ADR-005). The
  `saventa-summary` skill now also reads a **local meeting folder** (edited 2026-06-16). The auto-trigger
  (active feature) feeds Claude an **app-bundled** recipe + house style — **no skill install on each Mac**;
  each Mac needs only `claude` installed + logged in. CRM posting is on hold.
