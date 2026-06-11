# Agent Handoff — IN-meetings

<!--
Rewritten at every handoff. The incoming agent reads this + DECISIONS.md before starting.
Keep it short: last state, next steps, gotchas. History lives in git log.
-->

## Outgoing Agent
Claude Code · 2026-06-11

## Current State
**Design approved and Phase-0 de-risk prototypes DONE & verified live.** Work is on branch
`phase0-prototypes` (published to `github.com/YuvInv/IN-meetings`, private). `main` holds the design
baseline; `phase0-prototypes` is the active branch (ahead by the prototype + ADR-update commits).

- **Design complete:** `RESEARCH.md`, `DESIGN.md`, `adr/ADR-001..011`, `IMPLEMENTATION_PLAN.md`,
  `docs/notes/skill-contracts.md`. Every brief item resolved; load-bearing claims verified.
- **P1 — Hebrew ASR ✅ verified.** On-device fast (RTF ≈ 0.12 full / 0.10 short on M4), strong Hebrew.
  `initial_prompt` biasing FAILED → **deterministic post-correction** is the mechanism. `pipeline/benchmarks/`.
- **P2 — dual-track capture ✅ verified.** Core Audio tap + AVAudioEngine mic, two clean separate tracks,
  **only System Audio Recording permission** (no Screen Recording). `prototypes/p2-capture`.
- **P3 — call detection ✅ verified.** Core Audio per-process bidirectional audio I/O (input+output =
  call), app-agnostic, no special permission. `prototypes/p3-detect`.
- **P4 — in-person multi-speaker diarization ⏳ NOT done.** Needs a real in-person Hebrew recording.

## Next Session — START HERE: build the MVP app skeleton (IMPLEMENTATION_PLAN Phase 1, steps 1–3)
1. **Menu-bar app** (`LSUIElement`, launch-at-login via `SMAppService`) + onboarding TCC flow.
   **Developer-ID sign it** so System Audio Recording attaches to the app (headless binaries get silence).
   Use XcodeGen (like `~/repos/remote-camera`). Verify the shell launches in the menu bar before wiring.
2. **Wire P3 detection + manual Start** (menu-bar item + global hotkey) with **profile auto-pick**
   (live call → dual-track; else → in-person mic-only).
3. **Wire P2 capture** — reuse the verified pattern. Then: pipeline bridge → Hebrew transcription +
   post-correction → context package on disk → Drive. Verify each slice on a real meeting (don't batch).

## Gotchas the MVP MUST respect (learned + verified this session)
- **Tap write:** the tap is **interleaved float32** — create the `AVAudioFile` with the tap's exact
  processing format (`commonFormat` + `interleaved:true`) or `write(from:)` fails −50 (silent file).
- **TCC responsible process:** sign the app; an unsigned/headless binary gets digital silence from the tap.
- **Detection = bidirectional audio process**, NOT app/tab heuristics (that approach failed live).
- **ASR biasing = post-correction** (canonical entity + variant spellings), NOT `initial_prompt`.
- (See memory files: `call-detection-mechanism`, `coreaudio-tap-gotchas`.)

## Open Questions (for Yuval)
- Soniox opt-in cloud fallback acceptable, or strictly on-device?
- Auto-trigger default: one-click vs auto for calendar-matched founder meetings?
- Counsel review of ADR-010 (6 flagged items) — who/when?
- Coordinate the `--package` input mode in `~/repos/claude-skills` (ADR-005) — separate repo.

## Context
- Env: all Macs **macOS 26 / M3+/16GB**; Drive = **per-user OAuth** to a shared Team Drive.
- Downstream skills (`generate-mom`/`process-meeting`/`saventa-summary`) call the **Timeless API
  directly today — they don't read files**; the context package is a NEW contract (ADR-005).
- Strategic moat (verified): no shipping competitor combines local + Hebrew + vocabulary biasing.
- Security side-note (not this project): the desktop `timeless-access` skill embeds a live
  `TIMELESS_ACCESS_TOKEN` in plaintext — rotate/remove independently.
