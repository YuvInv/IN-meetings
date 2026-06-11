# Agent Handoff — IN-meetings

<!--
This file is rewritten at every handoff. The incoming agent reads it before starting work.
Keep it short: last state, next steps, gotchas. Do not append a history here — that's what git log is for.
-->

## Outgoing Agent
Claude Code

## Date
2026-06-11

## Current State
**Design approved ("let's go"). Phase 0 prototyping underway on branch `phase0-prototypes`.**
- **P1 (Hebrew ASR) — DONE, GO.** On real founder-meeting audio (M4/macOS 26, whisper.cpp Metal +
  ivrit turbo GGML): on-device fast (RTF ≈ 0.10, ~10× realtime) and Hebrew quality strong (beats
  Timeless on attribution). **Key finding: `initial_prompt` biasing does NOT work** (Latin terms
  regress proper nouns); **deterministic post-correction validated** as the replacement. ADR-003/004 +
  DECISIONS amended. Code+findings in `pipeline/benchmarks/` (data gitignored — confidential).
- **P3 (detection) — DONE, VERIFIED LIVE.** Mechanism corrected (Yuval): **Core Audio per-process
  audio I/O** — a process with both input+output running = a live call, named by bundle ID. No
  Automation/Accessibility/Screen-Recording permission; app-agnostic; rejects playback. Verified on
  M4/macOS 26 (YouTube→no; Meet w/ mic→`armed=YES Google Chrome`). The earlier app/tab approach failed
  and was dropped. ADR-001 + DECISIONS revised. `prototypes/p3-detect`.
- **P2 (capture) — BUILT, compile-checked. Runtime verification pending** (needs the System Audio
  Recording grant + a call with remote audio). Same Core Audio tap family. `prototypes/p2-capture`;
  run `swift run p2-capture 15` while audio plays + you talk; checklist in `prototypes/README.md`.
- **NEW requirement — ADR-011 recording modes (design done, not built):** manual Start (menu bar +
  hotkey) as fallback + primary path for **in-person** meetings; manual auto-picks profile (call→
  dual-track, else→mic-only); in-person = mic-only + **per-speaker diarization from v1** (manual-only
  trigger). New de-risk prototype **P4 (in-person multi-speaker diarization)** — needs a real in-person
  Hebrew meeting recording. ADR-001/002/003/005 + DESIGN + IMPLEMENTATION_PLAN updated.

---
_Prior state: Design phase complete — RESEARCH/DESIGN/ADRs/IMPLEMENTATION_PLAN committed (no app code)._
All Phase-1/2/3 deliverables from the brief are committed:
- `RESEARCH.md` (+ `docs/notes/research-raw/`) — landscape, ranked Hebrew ASR (ivrit.ai turbo, Apache-2.0,
  leaderboard-verified), macOS capture APIs, consent/legal, not-in-brief features/risks. Load-bearing
  claims verified against primary sources.
- `DESIGN.md` + `adr/ADR-001..010` — every brief item A–F resolved with one recommendation each.
- `IMPLEMENTATION_PLAN.md` — repo structure, MVP-first phases, 3 de-risk prototypes.
- `docs/notes/skill-contracts.md` — the real input contracts of the downstream Claude skills.

## Files Changed
- `RESEARCH.md`, `DESIGN.md`, `IMPLEMENTATION_PLAN.md` — created
- `adr/ADR-001..010*.md` + `adr/README.md` — created
- `DECISIONS.md` — ADR one-liners appended
- `docs/notes/skill-contracts.md`, `docs/notes/research-raw/*` — created
- `AGENTS.md` — project section filled in (design phase)

## Open Questions (for Yuval)
- Approve the design as-is, or change any ADR before scaffolding?
- Cloud ASR fallback (Soniox) — acceptable as an opt-in tier, or strictly on-device only?
- Auto-trigger default: one-click (current recommendation) vs auto for calendar-matched founder meetings?
- Counsel review of ADR-010 — who/when (6 items flagged)?

## Remaining Tasks
- [ ] Yuval reviews RESEARCH/DESIGN/ADRs/PLAN → approve or request changes
- [ ] On approval: build **Phase 0 prototypes first** (P1 Hebrew/code-switch ASR; P2 taps+nag+fullscreen
      banner on Tahoe; P3 Meet/browser detection) — go/no-go into DECISIONS.md
- [ ] Then MVP (Phase 1 in IMPLEMENTATION_PLAN.md)
- [ ] Coordinate the `--package` change in `~/repos/claude-skills` (ADR-005)

## Known Issues
- The research workflow hit a session limit mid-run; the **verification phase was completed manually in
  the main thread** for the load-bearing capture/ASR claims (see RESEARCH.md "Verification Status").
  Two claims are carried with explicit caveats to confirm during P2: (a) no monthly re-approval nag for
  audio-tap-only apps on Tahoe; (b) GGML/MLX quantized WER vs the leaderboard's CT2 fp16 numbers.
- Security side-note (not this project): the desktop `timeless-access` skill embeds a live
  `TIMELESS_ACCESS_TOKEN` in plaintext — rotate/remove independently.

## Context
- Confirmed by user: all Macs on **macOS 26 (Tahoe)**, weakest is **M3/16GB**, Drive auth = **per-user OAuth**.
- Key non-obvious finding: the downstream skills (`generate-mom`/`process-meeting`/`saventa-summary`) call
  the **Timeless API directly today** — they do NOT read files. The package is a NEW input contract → ADR-005
  adds a `--package` mode. Don't assume the skills already accept a folder.
- Strategic moat (verified): no shipping competitor combines local processing + Hebrew + vocabulary biasing.
- Raw research artifacts also at `/tmp/in-meetings-research/` (ephemeral) and mirrored in `docs/notes/research-raw/`.
