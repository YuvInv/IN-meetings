# ADR-009 — App architecture, language split & IPC

> **⚠️ Amended 2026-06-14/15** (see [DECISIONS.md](../DECISIONS.md)): the app is a **hybrid Dock + menu-bar** shell (amends the `LSUIElement`-only lifecycle) and **Drive sync is Swift-owned** (not under the Python pipeline). **Developer-ID sign/notarize/.dmg + launch-at-login + onboarding/TCC wizard are P0.** The file-based job-queue IPC + bundled-Python plan stand.

**Status:** Proposed · **Date:** 2026-06-11 · **Deciders:** Yuval (review)
**Brief item:** Phase 3 (stack & communication) · **Research:** RESEARCH.md §4

## Context

Capture and UI must be native Swift (Core Audio taps, AVAudioEngine, ScreenCaptureKit, NSPanel,
EventKit, Keychain are all Swift/native). The ASR/diarization/context/Drive pipeline is naturally
Python (whisper.cpp bindings, senko, the MCP-backed assemblers, Google API client). The two must
communicate cleanly, survive crashes, and be observable.

## Decision

**Swift/SwiftUI menu-bar app (orchestrator + capture + UI) + a bundled Python pipeline, talking over a
file-based job queue with JSON status.**

**Swift app (`INV Meetings.app`, `LSUIElement`):**
- Detection (ADR-001), capture (ADR-002), banner + dashboard (ADR-001/007), SQLite owner, Drive upload
  trigger, Keychain, launch-at-login, onboarding wizard.
- Owns the menu-bar lifecycle; spawns pipeline jobs; reflects their status in the UI.

**Python pipeline (bundled venv inside the app bundle, or a pinned `uv`/`pyenv` env):**
- Context assembler (ADR-004), ASR + diarization (ADR-003), packaging (ADR-005), Drive sync (ADR-006),
  Claude trigger (ADR-008). Invoked per meeting as a one-shot job (not a long-running daemon).

**IPC — file-based job queue + JSON status (chosen for simplicity, observability, crash-safety):**
- The Swift app writes a **job file** (`jobs/<meeting-id>.job.json`: package path, options, mode) and
  launches the pipeline (`python -m in_meetings_pipeline run <job>`), or drops it in a watched `jobs/`
  dir processed by a short-lived worker.
- The pipeline writes **status** back as JSON (`jobs/<meeting-id>.status.json`: phase, progress, errors,
  outputs) and updates SQLite rows the dashboard reads. The Swift app tails status (file watch) to
  update the UI.
- **Why not a socket/gRPC/XPC:** for ~5 users and per-meeting batch work, files are debuggable by
  hand, survive either process crashing (the job/state is on disk), need no port or service, and make
  resume trivial. XPC/sockets add ceremony with no benefit at this cadence. Revisit only if we add
  live/streaming transcription (which we've scoped out for v1).
- **Crash-safety:** a job is idempotent and resumable from its last completed phase (raw folder →
  context → transcript → package → sync → claude), so a killed pipeline re-runs cleanly.

**Packaging & distribution:** internal **Developer ID signing + notarization** (not App Store). This
is deliberate — it lets us use the private TCC SPI for the audio-permission check (ADR-002) and bundle
the Python env, which the App Store sandbox forbids. Acceptable for a 5-person internal tool. Bundle
the whisper.cpp binary + ivrit GGML model (or fetch the model on first run to keep the app small).

**Onboarding wizard (first launch):** walk the four TCC grants in order with explanations —
**Microphone**, **System Audio Recording Only** (provoke the prompt by starting a throwaway tap, since
there's no request API), **Automation** (per browser, for tab URLs), **Calendar** (EventKit) — plus
**Google Drive OAuth** (ADR-006) and a check that `claude` is on PATH (ADR-008). Detect denials and
show how to fix in System Settings. This is the low-friction rollout the brief requires.

## Options considered

| Option | Why not |
|--------|---------|
| Pure Swift (port ASR to Swift/WhisperKit) | Throws away the ivrit GGML/MLX + senko + MCP-assembler Python ecosystem; re-implementation risk on the make-or-break ASR path. |
| Pure Python (Swift only a thin shell) | Capture/UI need native APIs; Python can't do the taps/NSPanel/EventKit work well. |
| Long-running Python daemon + socket/XPC | More moving parts, port/lifecycle management, harder to debug; unnecessary for per-meeting batch jobs. |
| Embed Python via PythonKit in-process | Couples crashes; harder to update the pipeline independently; the dual-agent/dev workflow prefers separable parts. |

## Consequences

- **Good:** each side uses its natural ecosystem; loose coupling via files = observable, crash-safe,
  resumable; pipeline can be developed/tested standalone (great for the Prototype-1 ASR benchmark);
  internal signing unblocks the tap permission check.
- **Costs/risks:** bundling/locating a Python env in a signed app needs care (venv path, notarization
  of binaries, model download); file-watch IPC has minor latency (fine for batch); two languages =
  two toolchains in CI. The SQLite schema and the job/status JSON are shared contracts — version them
  and keep a fixture in the repo. Internal signing means we maintain a Developer ID + notarization step.
