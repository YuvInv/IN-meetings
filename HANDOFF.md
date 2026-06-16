# Agent Handoff — IN-meetings

<!--
Rewritten at every handoff. The incoming agent reads this + DECISIONS.md before starting.
Keep it short: last state, next steps, gotchas. History lives in git log.
-->

## Outgoing Agent
Claude Code · 2026-06-16

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

**Shipped + MERGED to `main` (2026-06-16):** [PR #10](https://github.com/YuvInv/IN-meetings/pull/10) **+
[PR #11](https://github.com/YuvInv/IN-meetings/pull/11) BOTH MERGED.** #10 = P0 reliability (VAD bundled +
pipeline failures surfaced), P1 call video (SCK window → `meeting.mp4` → Drive → playback), Drive folder
picker (Google Picker web view), video-detail crash fix. #11 = A/V-sync rewrite (one SCK stream, one clock)
+ ~6× smaller recordings (720p / 2 Mbps HEVC passthrough mux, 1.86 GB→~300 MB) + speaker naming + the
committed Picker key. All live-verified. **Local `main` synced to `origin/main` `7b3a8d0`.**

> ⚠️ **Branch-hygiene note (2026-06-16):** the prior session-wrap commit `5398a43` (this spec + the
> DECISIONS / IMPLEMENTATION_PLAN / HANDOFF updates) sat on the **deleted** `feat/reliability-video-drive-picker`
> tip and was **never merged** into `main` (PR #11 merged only up to `f1fe477`). Those 4 files were
> **restored from `5398a43`** onto `feat/saventa-summary-autotrigger` (working tree), so they ride along in
> this branch's PR. `main` on its own is missing them until this branch merges.

**🟢 BUILT (code complete + end-to-end verified; pending UI live-test) on branch `feat/saventa-summary-autotrigger`: the `saventa-summary` auto-trigger.**
Spec: `docs/superpowers/specs/2026-06-16-saventa-summary-autotrigger.md` (the **house-style file list is
settled there** — the earlier open Q is resolved; use exactly that non-CRM vc-context set). Flow: meeting
done → `JobBridge.indexCompletedPackage` kicks a new **`SummaryRunner`** → headless `claude -p` over the
package, fed an **app-bundled recipe + house-style** via `--append-system-prompt` (**NOT** a globally-installed
skill) → Claude writes `<folder>/summary.md` → dashboard "Summary" panel + Drive sync. Auto-on-finish
(file-only, safe). **⚠️ Sevanta/CRM posting is ON HOLD — do NOT surface it.**
- **Integration map (verified this session):** `JobBridge` (trigger after `driveBackup` in
  `indexCompletedPackage`; reuse `.jobBridgeDidFinish` + a new `.summaryDidFinish`), `MeetingStore` (migration
  **v3** adds `summaryState`/`summaryError`/`summarySessionId` + an `updateSummaryState(…)` method),
  `DriveSync.textFileNames += "summary.md"` + `DriveAuth.reuploadPackageFile` (handle `.md` MIME),
  `CaptureSettings.autoSummary` (default **on**), `MeetingDetailView` Summary panel. Recipe bundled under
  `Apps/INMeetings/INMeetings/Resources/skills/saventa-summary/` (XcodeGen auto-bundles the `Resources` tree;
  run `make gen` after adding files).
- **Recipe source to vendor:** the **edited** installed SKILL.md at
  `~/Library/Application Support/Claude/.../skills/saventa-summary/SKILL.md` (local-folder mode + writes
  `summary.md`); house-style = `~/repos/claude-skills/vc-context/{critical-analysis,investment-thesis,
  josh-preferences,writing-style}.md` + `vc-context/mom-examples/{anti-patterns,example-summary,
  style-analysis}.md`. **Exclude** `crm-mappings.md` + `sevanta-api-reference.md`.

**Build status (2026-06-16):** all 8 tasks done — vendored recipe + 7 house-style files (`Resources/skills/
saventa-summary/`, bundled as an XcodeGen folder reference, **verified present in the built `.app`**);
`MeetingStore` v3 (`summaryState`/`summaryError`/`summarySessionId` + `updateSummaryState`); `CaptureSettings.
autoSummary` (default on); `SummaryRunner` (Core) + `DriveSync.syncSummary` / `DriveBackup.
syncSummaryIfConfigured`; `JobBridge` auto-trigger (calls only, sequenced after Drive) + public `summarize(…)`;
dashboard Summary panel + Settings toggle (jobBridge threaded App → DashboardWindow → RecordingStore). **Core
`swift test` 90/90 green** (+8 SummaryRunner/Drive), **`make build-mac` green**. **END-TO-END VERIFIED:** a real
`claude -p` run with the bundled recipe over the golden fixture wrote a correctly-formatted `summary.md`
(literal asterisks preserved, transcript-only, blanks unpadded), exit 0, parseable `session_id`. **⏳ Still
Yuval's live-test (needs the running app):** the dashboard Summary panel states + the full record→auto-summary
flow on a real call → Drive. Checklist: `docs/manual-tests-saventa-summary.md`. **NOT committed yet.**

**Roadmap changes this session (DECISIONS 2026-06-16 + IMPLEMENTATION_PLAN):**
- **Auto-stop when a meeting ends → now a v1 MUST-HAVE** (P1, was P2). Debounced prompt, never silent (the
  2026-06-14 decision). **Research how other recorders detect meeting-end** before designing.
- **Upload an audio file for transcription → new MUST-HAVE, NOT P0** (P1). Import a file (e.g. a phone
  recording) → normal pipeline → package → dashboard/Drive; no live capture. Design later.
- **User-defined post-meeting skills → FUTURE, not designed yet.** A Settings surface for user-described
  workflows; generalizes this saventa-summary trigger. Don't design now.

**Remaining roadmap gaps:** onboarding / TCC wizard (Mic + System-Audio + **Screen-Recording** + Google —
the adoption gate, still TODO); **Ship** phase (Developer-ID sign + notarize + `.dmg` + launch-at-login +
Sparkle — done LAST, gated on a $99 Apple Developer account; runbook `docs/distribution-setup.md`); the new
**auto-stop** + **audio-upload** must-haves; a global cache-size cap. The in-app "AI overview" panel stays
out of v1. Hybrid app shell ✅ (PR #8); company naming+edit ✅ (PR #9).

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
- **Company naming** (gap #2, P1): edit/rename UI ✅ (PR #9). Inference is still calendar-external-domain only
  → "Unknown company" on no-match / internal-only / fetch-fail; title + transcript fallbacks designed but unused.
- **Saventa-summary auto-trigger** (active feature, designed): build `SummaryRunner` + the bundled recipe per
  the spec; `summary.md` contract → dashboard panel + Drive. Live-verify `claude -p` runs the recipe headless.
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
