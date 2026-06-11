# Agent Handoff — IN-meetings

<!--
Rewritten at every handoff. The incoming agent reads this + DECISIONS.md before starting.
Keep it short: last state, next steps, gotchas. History lives in git log.
-->

## Outgoing Agent
Claude Code · 2026-06-11

## Current State
**MVP Phase 1 in progress.** Branch **`feat/mvp-app-skeleton`** (off `main`; `main` == `phase0-prototypes`,
prototypes merged). Phase-0 prototypes (P1 ASR, P2 capture, P3 detection) all verified; **P4 in-person
diarization still pending.** The Swift menu-bar app now exists under `Apps/INMeetings` + core lib
`Sources/INMeetingsCore` (XcodeGen + root `Makefile`; `make verify-mac`). **Slices 1–3 done, verified live, committed:**

- **Slice 1 ✅** menu-bar shell (`LSUIElement` `MenuBarExtra`), signed **Apple Development** (team A6C6D257QN),
  bundle `com.in-venture.in-meetings`. Launches in the menu bar (`f45df9d`).
- **Slice 2 ✅** P3 detection wired into the menu (idle/armed) + manual **Start/Stop** (menu + global **⌃⌥⌘R**
  via Carbon, no Accessibility) + **profile auto-pick** (call→dual-track, else→in-person) + live menu-bar
  timer (`b2d3fb3`, `2bde2fa`).
- **Slice 3 ✅** dual-track capture (`SystemAudioTap` + `MicRecorder` + `CaptureSession`) → per-meeting folder
  under Application Support; mic-permission request + Info.plist usage strings; post-recording self-diagnostic
  `Last: mic X dB · sys Y dB`. Verified live on a Google Meet call: **mic −15 dB / system −4 dB** (`3faa336`).

## Next — START HERE: slice 4 (pipeline bridge → Hebrew transcription)
4. **Job bridge** (file queue + JSON status IPC, ADR-009) from the app to a **Python pipeline**; on Stop,
   enqueue the recording. Pipeline: **ivrit-ai turbo GGML on whisper.cpp Metal** (biasing deferred to Phase 2 —
   ship unbiased) + **deterministic post-correction** (P1 finding) + **senko** diarization on the system track +
   Me/Them merge → `transcript.json`/`.txt`. Verify on a real recording (eyeball Hebrew).
5. Context **package** on disk (ADR-005 schema; `schema/` is currently empty) + SQLite index (GRDB).
6. **Drive sync** (per-user OAuth, company-first layout, ADR-006). Verify each slice on a real meeting — don't batch.

## Gotchas the MVP MUST respect (verified)
- **TCC grant needs a relaunch:** mic + System Audio Recording grants take effect only on an app launch
  *after* granting — first recordings are **−91 dB silence on BOTH tracks** until relaunch. Onboarding must
  force/guide a relaunch. The in-app `Last: mic/sys dB` readout is the capture-health check. (memory: `coreaudio-tap-gotchas` #3.)
- **Signing:** **Apple Development is sufficient for local-dev capture** (avoids the digital-silence gotcha);
  Developer-ID + notarization is a **Phase-5** rollout concern, NOT needed now. (Corrects the old handoff.)
- **Tap write:** interleaved float32 — pin the `AVAudioFile` to the tap format or `write(from:)` fails −50.
- **Detection = bidirectional audio process**, not app/tab heuristics. **ASR biasing = post-correction**, not `initial_prompt`.
- (memory: `call-detection-mechanism`, `coreaudio-tap-gotchas`.)

## Open Questions / follow-ups (for Yuval)
- **Onboarding TCC wizard is minimal** (mic request + tap attempt + error/relaunch hint). A proper multi-step
  wizard that *forces a relaunch after first grant* is a deferred polish item.
- Soniox opt-in cloud fallback acceptable, or strictly on-device? Auto-trigger default (one-click vs auto)?
- Counsel review of ADR-010 (6 flagged items). Coordinate the `--package` mode in `~/repos/claude-skills` (ADR-005).

## Context
- Env: all Macs **macOS 26 / M3+/16GB**; Drive = **per-user OAuth** to a shared Team Drive. Toolchain note: a
  fresh Xcode 26.5 needed `sudo xcodebuild -runFirstLaunch` before app builds worked.
- Downstream skills (`generate-mom`/`process-meeting`/`saventa-summary`) call the **Timeless API directly today —
  they don't read files**; the context package is a NEW contract (ADR-005).
- Security side-note (not this project): the desktop `timeless-access` skill embeds a live `TIMELESS_ACCESS_TOKEN`
  in plaintext — rotate/remove independently.
