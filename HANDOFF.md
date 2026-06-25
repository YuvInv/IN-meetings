# Agent Handoff — IN-meetings

<!--
Rewritten at every handoff. The incoming agent reads this + DECISIONS.md before starting.
Keep it short: last state, next steps, gotchas. History lives in git log.
-->

## Outgoing Agent
Claude Code · 2026-06-24 (v1 breadth features session)

## Current State
**Branch `feat/v1-breadth-features` implements the 5 v1 breadth features + distribution pipeline +
summary-pane bugfix + custom summaries.** All build + unit-test + code-review green: **Core 265/0**,
`make build-mac` SUCCEEDED. **NOT yet pushed to remote.**

**What's on this branch (full):**
- **A1–A6 + DIST**: audio device picker, summary recipe registry, queue view, launch-at-login + version,
  dictation (on-device hotkey), unsigned-DMG distribution pipeline (see DECISIONS 2026-06-24).
- **Summary-pane bugfix** (`ee095c2`): `showSummaryPane` changed `@AppStorage` → `@State` so collapsing
  the pane on one meeting doesn't hide it globally (see DECISIONS 2026-06-25 first entry).
- **Custom summaries** (3 tasks, see DECISIONS 2026-06-25 second entry):
  - **In-app recipe editor**: Settings → Summary create/edit/delete sheet; saved to
    `~/Library/Application Support/IN Meetings/Recipes/<slug>/recipe.md` + `name.txt`.
  - **Multiple summaries per meeting**: per-recipe `summaries/<recipeId>.md` + `summary.md` mirror;
    migration v5 `meetingSummary` table; `SummaryRunner` writes per-recipe with per-(meeting,recipe)
    in-flight guard + rollup update; Drive syncs per-recipe files.
  - **Meeting-page UI**: summary switcher across a meeting's recipes + "Summarize with… ▾" per-meeting
    menu + Copy/Re-run/Delete per summary; `SummaryReconcile` deletes cleanly (no phantom entries,
    Queue never stuck).

Live-verification pending with Yuval (real device / real recording / dictation AX grant /
launch-at-login post-install / queue view on a real call / **custom summaries: create a recipe, run two
recipes on one meeting, switch/Copy/Re-run/Delete**).

`main` is at the PR #19 merge (rename INV Meetings). The breadth branch was cut from the post-rename `main`.

**What's on this branch:**
- **A1** — Settings → Audio tab: input-device picker (CoreAudio UID enumeration) + live level meter +
  adaptive gain (default OFF — mic is the ASR source of truth).
- **A2** — Summary recipe registry: bundled `Resources/skills/*` + user `~/Library/…/Recipes/*`; active
  recipe off-main `UserDefaults`; `makeArguments` recipe-agnostic; 2nd bundled `brief-summary` recipe.
  Settings → Summary tab (autoSummary toggle moved here).
- **A3** — Queue / Processing dashboard view: `JobBridge` now surfaces `progress` + `activeMeetingID`;
  live progress via computed `QueueModel.items` in SwiftUI body; per-phase labels, progress bar,
  Reveal-pipeline.log + Retry. Pure `QueuePhase.derive` unit-tested in Core.
- **A4** — Settings → General: launch-at-login (`SMAppService.mainApp` behind `LaunchAtLoginManaging`
  protocol) + app version. Sparkle update-check UI deliberately NOT shipped (dead no-op pre-account;
  inert seams only).
- **A6** — Global-hotkey on-device dictation → paste-at-cursor. `whisper-cli` direct (not pipeline) for
  latency; toggle semantics; He ⌃⌥⌘D / En ⌃⌥⌘E; AX grant contextual (not onboarding gate); default
  OFF; non-activating NSPanel overlay; 30s spawn watchdog.
- **DIST** — `.github/workflows/release.yml` (unsigned `.dmg` → GitHub Releases on `v*` tag, works NOW
  with no Apple account); `docs/appcast.xml` template; "Release hosting + auto-update" section in
  `docs/distribution-setup.md`. Architecture: GitHub Releases + GitHub Pages + Sparkle 2 (EdDSA).
  Account-gated steps activate when the $99 Developer account secrets are provisioned.

## Next — START HERE

**⏳ PENDING LIVE VERIFICATION (Yuval):**
1. Audio device picker — select a non-default mic in Settings → Audio, record, verify correct device used.
2. Level meter — confirm it moves on mic input.
3. Recipe selector — switch to `brief-summary`, run auto-summary, verify shorter output.
4. Queue view — confirm progress bar + per-phase labels during a real pipeline run.
5. Launch-at-login — install the app (make dmg → drag to /Applications), enable in Settings, reboot, confirm
   quiet background launch.
6. Dictation — grant AX when prompted, ⌃⌥⌘D in a text field, speak, ⌃⌥⌘D again, confirm Hebrew pasted.
7. Unsigned DMG CI — push a `v*` tag to a fork / test repo, confirm the workflow runs and produces a GitHub
   Release with the DMG attached.
8. Custom summaries — Settings → Summary: create a recipe (name + instructions), save; open a meeting;
   "Summarize with… ▾" → run the new recipe; confirm `summaries/<id>.md` appears; run a second recipe;
   use the switcher; Copy/Re-run/Delete each entry; confirm no phantom entry in Queue view.

**After live-verify:** push branch → open PR → merge → activate the account-gated distribution (Developer
ID + notarization + Sparkle) when the $99 Apple Developer account lands.

**Remaining v1 gaps after this branch:**
- **Ship** — Developer-ID sign + notarize + Sparkle (account-gated; the workflow + appcast template
  already exist; runbook `docs/distribution-setup.md`).
- **Global cache-size cap** — delete oldest synced meetings beyond N GB (still TODO).

**Note (scope):** this project has **NO Saventa/CRM connection** — the auto-summary writes `summary.md`
only. Do not surface CRM posting as a feature or task.

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
