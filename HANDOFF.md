# Agent Handoff — IN-meetings

<!--
Rewritten at every handoff. The incoming agent reads this + DECISIONS.md before starting.
Keep it short: last state, next steps, gotchas. History lives in git log.
-->

## Outgoing Agent
Claude Code · 2026-06-14

## Current State
**MVP Phase 1: detect → dual-track record → on-device Hebrew transcription → speaker diarization works end to end.**
Slices **1–4c are merged to `main`** (PRs #1 + #2). **Current branch: `feat/mila-harvest`** (off `main`).

### This session (2026-06-14): evaluated `island-io/mila` → continue ours + harvest (DECISIONS 2026-06-14)
- **Harvest 0 ✅** Apache-2.0 attribution: `NOTICE`, `THIRD_PARTY_NOTICES.md`, `licenses/mila-LICENSE-2.0.txt`;
  per-file `// Adapted from Mila …` headers on derived files.
- **Harvest 1 ✅ model download on launch** — `Sources/INMeetingsCore/Models/{ModelManager,ModelCatalog}.swift`
  (`@Observable`; URLSession download + streaming SHA-256 verify + atomic install; SHA pinned + verified vs HF LFS oid).
  `JobBridge.spawn` now sets **`IN_MEETINGS_MODEL`** to the app-managed copy when present; `INMeetingsApp` downloads
  on launch and **gates Start until `.ready`**. 4 new tests; `swift build` + `swift test` (10/10) + `make build-mac` green.
  **Verified live**: launch kicks the download (CFNetwork temp grew past 19 MB); full install + SHA match confirmed.
- **Harvest 3 ✅ "Record now" overlay** — `Apps/INMeetings/INMeetings/MeetingPrompt{Coordinator,Overlay}.swift` +
  `Sources/INMeetingsCore/Detection/MeetingDetectionSettings.swift`. Liquid Glass non-activating `NSPanel`, fires on
  our `CallDetector` **idle→armed** edge (app-agnostic; seeds `lastStatus=.idle` so launching mid-call still prompts);
  Record / Not now (1 h snooze) / Don't-ask-for-app; menu toggle + Resume. 4 new tests. **Verified live**: card
  auto-appears on a real Zoom call. Gotcha fixed: the DEBUG preview's buttons are no-ops (an earlier preview "Not now"
  ran the real `snooze()` and silently suppressed prompts for an hour — looked like a broken auto-trigger).

Slices, all verified **live**:
- **1–4b ✅** (in `main`): menu-bar app, P3 detection + manual Start/Stop + global ⌃⌥⌘R hotkey, dual-track
  capture, Swift↔Python job bridge (ADR-009), real Hebrew transcription (whisper.cpp ivrit-turbo + post-correction).
- **4c ✅** **speaker diarization (senko)** — `pipeline/in_meetings_pipeline/diarize.py` + profile-aware
  `attribute_speakers` in `__main__`. **Bake-off chose senko over pyannote** (senko matched Timeless
  ground-truth counts: 2 on the 6-min clip, 3 on the full 51-min `prelligence`; RTF ~0.001–0.004; no HF
  gating — see DECISIONS 2026-06-11 slice 4c). Verified live end-to-end on real Hebrew: **in-person** →
  `Speaker 1/2` on the mic; **call** → `Me` (mic) + `Speaker 1/2` (system). `transcript.json` now carries a
  `speakers[]` table + `diarized` flag. 8 unit tests (`pipeline/tests/test_diarize.py`), ruff clean, `swift build` green.

## Next — START HERE: slice 5 (context package + SQLite index)
- Write the **context package** to disk per **ADR-005** (the stable contract the Claude skills consume) —
  `schema/` is still empty (only `fixtures/`). Freeze the schema, emit a golden fixture, mirror it for
  contract tests both sides. The `transcript.json` shape (segments + `speakers[]` + `diarized`) feeds this.
- Add the **SQLite index** (ADR-006) — per-meeting folder cache + FTS5 later (dashboard is Phase 4).
- Then **slice 6**: Drive sync (per-user OAuth, company-first layout — ADR-006). Verify each on a real meeting.
- **Additive slices** (must NOT block the core spine — plan: `~/.claude/plans/i-have-a-questions-cached-lark.md`).
  **H3 ✅ done.** Pending: **V1** call video capture (SCK, ON by default for calls, window-only — adds the Screen
  Recording grant, reverses the no-Screen-Recording posture; DECISIONS 2026-06-14) · **V2** "meeting done?" auto-stop
  prompt (armed→idle, debounced ~10–15 s, prompt-not-silent, keep-recording-if-ignored) · **H4** dashboard views
  (after slices 5/6) · **H2** packaging + Sparkle — gated on Developer ID / notarization / appcast / EdDSA keys.

## Gotchas (verified)
- **senko needs Python <3.14**; system `python3` is **3.14** → pipeline runs in a **pinned 3.11 venv**
  (`pipeline/.venv`). `make`/dev: `cd pipeline && uv sync --group dev`. `JobBridge.defaultPython` now spawns
  `.venv/bin/python` (override: `IN_MEETINGS_PYTHON`). senko on Mac uses **CoreML/ANE** (no torch) + downloads
  its models on first run (~20s one-time).
- **senko wants 16 kHz mono 16-bit** input; `diarize.py` normalizes (soundfile + scipy) before calling it.
- **TCC grant needs a relaunch** (mic + System Audio Recording): first recordings are −91 dB silence until a
  relaunch *after* granting. In-app `Last: mic/sys dB` is the capture-health check. (memory: `coreaudio-tap-gotchas`.)
- **Tap write:** interleaved float32 — pin `AVAudioFile` to the tap format or `write(from:)` fails −50.
- **Pipeline is spawned, not compiled in** — editing `pipeline/` takes effect without rebuilding the app.
- **Model download (H1):** app fetches `ivrit-large-v3-turbo.ggml.bin` (~1.6 GB, SHA-pinned) to
  `~/Library/Application Support/IN Meetings/Models/` on launch; `JobBridge` sets `IN_MEETINGS_MODEL` to it when
  present, else `asr.py` uses the `pipeline/benchmarks/models/` copy. brew `whisper-cli` has **no CoreML** → mila's
  ANE encoder was intentionally dropped (a Phase-5 `WHISPER_COREML` build would re-enable it).
- Detection = bidirectional audio process; ASR biasing = post-correction (no-op until Phase-2 vocab).

## Open / follow-ups
- **⏳ PENDING LIVE VERIFICATION (MVP-accepted, Yuval 2026-06-11):** diarization quality on a **real multi-party
  video call** is untested — Yuval couldn't record one and accepted it for the MVP; he'll flag if it's not good
  enough once real calls run. The call path is so far only verified on a *synthetic* 2-track meeting. Every job
  now writes a per-meeting **`pipeline.log`** (child stdout/stderr + a `diarization …` summary line) → review
  those after the first real calls to judge it. Also **DER** (turn accuracy) is sane-by-eye but not numerically
  measured — a DER harness vs a hand-labeled Hebrew reference is a follow-up.
- pyannote `community-1` is the documented fallback (gated; needs HF token) — not wired into the pipeline.
- Onboarding TCC wizard is minimal — a wizard that **forces a relaunch after first grant** is deferred.
- Soniox fallback? Auto-trigger default? Counsel review of ADR-010. Coordinate `--package` in `~/repos/claude-skills` (ADR-005).

## Context
- Env: macOS 26 / M3+/16GB; Drive = per-user OAuth to a shared Team Drive.
- Pipeline dev paths hardcoded in `JobBridge` (overridable via `IN_MEETINGS_PIPELINE_DIR`/`IN_MEETINGS_PYTHON`/`IN_MEETINGS_MODEL`); Phase 5 bundles them.
- Downstream skills call the Timeless API directly today — the context package is a NEW contract (ADR-005).
