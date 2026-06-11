# Agent Handoff — IN-meetings

<!--
Rewritten at every handoff. The incoming agent reads this + DECISIONS.md before starting.
Keep it short: last state, next steps, gotchas. History lives in git log.
-->

## Outgoing Agent
Claude Code · 2026-06-11

## Current State
**MVP Phase 1 well underway — detect → dual-track record → on-device Hebrew transcription works end to end.**
Two branches (Phase-0 prototypes P1/P2/P3 verified; **P4 in-person diarization still pending**):

- **`feat/mvp-app-skeleton`** → **PR #1 open against `main`** (https://github.com/YuvInv/IN-meetings/pull/1): slices 1–4a.
- **`feat/mvp-pipeline-transcription`** (stacked off the above; **current branch**): adds slice 4b. Rebase onto
  `main` once PR #1 merges, then open a follow-up PR.

Slices, all verified **live**:
- **1 ✅** menu-bar shell (`LSUIElement` `MenuBarExtra`), XcodeGen + `Makefile`, signed **Apple Development** (`f45df9d`).
- **2 ✅** P3 detection in menu + manual Start/Stop (menu + global **⌃⌥⌘R** Carbon, no Accessibility) + profile auto-pick + live timer (`b2d3fb3`,`2bde2fa`).
- **3 ✅** dual-track capture (`SystemAudioTap`+`MicRecorder`+`CaptureSession`) + in-app `Last: mic/sys dB` self-diagnostic. Verified mic −15/sys −4 dB (`3faa336`).
- **4a ✅** Swift↔Python **job bridge** (file IPC, ADR-009): Stop → `job.json` → spawn `python -m in_meetings_pipeline` → watch `status.json`; menu shows phase (`21487bb`).
- **4b ✅** real **Hebrew transcription** (whisper.cpp ivrit-turbo + post-correction hook) → `transcript.json`/`.txt`, Me/Them by track (`082c16c`). Verified live: code-switched VC terms (CTO/CEO/ARR) transcribed correctly inside Hebrew, RTF ~0.16.

## Next — START HERE: slice 4c (diarization)
- **Install senko** (not present): `uv` venv in `pipeline/` (`uv add senko` or pin). Then diarize the **system track** (calls) / the **mic track** (in-person, this is P4) → split multiple speakers *within* a track and refine the Me/Them merge. `pipeline/in_meetings_pipeline/` (add `diarize.py`; wire into `__main__`). Verify on a real multi-speaker recording.
- Then **slice 5** (context **package** schema — `schema/` is empty — + SQLite/GRDB index) and **slice 6** (Drive sync, per-user OAuth, ADR-006). Verify each on a real meeting.

## Gotchas (verified)
- **TCC grant needs a relaunch:** mic + System Audio Recording grants take effect only on a launch *after* granting — first recordings are −91 dB silence until relaunch. Onboarding must force a relaunch. The in-app `Last: mic/sys dB` readout is the capture-health check. (memory: `coreaudio-tap-gotchas` #3.)
- **Signing:** Apple Development is sufficient for local-dev capture; Developer-ID + notarization is **Phase 5**.
- **Tap write:** interleaved float32 — pin `AVAudioFile` to the tap format or `write(from:)` fails −50.
- **Pipeline is spawned, not compiled in** — editing `pipeline/` takes effect without rebuilding the app.
- Detection = bidirectional audio process; ASR biasing = post-correction (no-op until Phase-2 vocab).

## Open / follow-ups
- **PR #1** is ~1.3k lines → run **`/codex:adversarial-review`** before merging (project convention).
- Onboarding TCC wizard is minimal — a proper wizard that **forces a relaunch after first grant** is deferred.
- Soniox fallback? Auto-trigger default? Counsel review of ADR-010. Coordinate `--package` in `~/repos/claude-skills` (ADR-005).

## Context
- Env: macOS 26 / M3+/16GB; Drive = per-user OAuth to a shared Team Drive. Fresh Xcode 26.5 needed `sudo xcodebuild -runFirstLaunch`.
- Pipeline dev paths hardcoded in `JobBridge` (overridable via `IN_MEETINGS_PIPELINE_DIR`/`IN_MEETINGS_PYTHON`/`IN_MEETINGS_MODEL`); Phase 5 bundles them.
- Downstream skills call the Timeless API directly today — the context package is a NEW contract (ADR-005).
