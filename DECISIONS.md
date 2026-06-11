# Architectural Decisions

This file tracks significant architectural decisions made during development of IN-meetings. Both Claude Code and Codex CLI read this before making changes that affect project architecture. Append-only — do not edit or remove past entries.

## Format

```
### YYYY-MM-DD — <short title>
- **Agent**: Claude Code | Codex CLI
- **Decision**: What was decided
- **Rationale**: Why this approach was chosen
- **Alternatives considered**: What else was evaluated and why it was rejected
- **Consequences**: Tradeoffs accepted
```

---

<!-- Decisions will be added here as development progresses. Newest last. -->

### 2026-06-11 — P1 prototype: context injection is post-correction, not prompt biasing
- **Agent**: Claude Code
- **Decision**: Based on the P1 ASR benchmark on real founder-meeting audio (M4/macOS 26, whisper.cpp Metal + ivrit-ai turbo GGML), the context-injection mechanism is **deterministic entity post-correction**, not Whisper `initial_prompt` biasing. ADR-003 and ADR-004 amended accordingly. Evidence: `pipeline/benchmarks/P1-FINDINGS.md`.
- **Rationale**: Measured — `initial_prompt` with Latin proper nouns *regressed* names the model otherwise got right (אלגוליון/Algolion → אלכוהוליון/"alcohol-ion", 6×); Hebrew-script terms were neutral; neither fixed the hardest term ("IN Venture"). The forced-Hebrew fine-tune won't emit Latin and its prompt-following is weak (matches the research's catastrophic-forgetting caveat). Post-correction (canonical entity + variant spellings → whole-token replace) was validated: deterministic, no regressions, and yields the canonical Latin spellings the Claude skills want.
- **Alternatives considered**: Latin-script `initial_prompt` (regresses — rejected); Hebrew-script `initial_prompt` (neutral — kept only as an optional light primer, no Latin terms); model fine-tuning for code-switching (out of scope for now).
- **Consequences**: ADR-004 emits a correction vocabulary (canonical + variants) rather than a ranked prompt word-list; the CI check becomes a post-correction fixture test; a fuzzy/edit-distance pass for unseen variants is the next refinement. On-device default is confirmed (speed + quality both pass).
- **Also confirmed GO**: on-device Hebrew ASR is fast (RTF ≈ 0.10, ~10× realtime) and high quality on the team hardware floor; beats Timeless on speaker attribution (Timeless gave only generic Speaker 1/2/3).

### 2026-06-11 — Design-phase ADRs (ADR-001 … ADR-010)
- **Agent**: Claude Code
- **Decision**: Recorded the full design in `DESIGN.md` + `adr/`. One-line summaries (each links to its ADR):
  - **[ADR-001](adr/ADR-001-call-detection-trigger-ux.md)** — Multi-signal detection (running-app ∪ mic-in-use ∪ calendar ∪ browser-tab via AppleScript); **prompt-to-record** (not silent auto) with a **ring-buffer** so pre-confirm audio isn't lost; non-activating `NSPanel` over fullscreen; menu-bar `LSUIElement`.
  - **[ADR-002](adr/ADR-002-capture-pipeline.md)** — **Core Audio process tap** (remote/system, per-process) + **AVAudioEngine** (mic) as **two WAV tracks**; raw mic + **offline AEC**; **video off by default** (SCK/HEVC opt-in); mic-idle-debounced auto-stop. No virtual driver, no Screen Recording TCC for audio.
  - **[ADR-003](adr/ADR-003-transcription-engine.md)** — Primary **`ivrit-ai/whisper-large-v3-turbo`** on whisper.cpp Metal (GGML), MLX optional; `initial_prompt` biasing (≤224 tokens, terms last, pinned revision + regression test); **senko** diarization on the system track only; `transcript.json`+`.txt`; **Soniox** opt-in cloud fallback; Vision OCR for slides (opt-in).
  - **[ADR-004](adr/ADR-004-context-assembler.md)** — Match meeting → Calendar event → Saventa + Dealigence → **ranked biasing vocabulary** + `context.md` (priors only); graceful degradation when unmatched.
  - **[ADR-005](adr/ADR-005-context-package-contract.md)** — Freeze the package schema as the contract; add a **`--package <path>` local-input mode** to `saventa-summary`/`generate-mom`/`process-meeting` alongside the Timeless path; richer fields enable Hebrew-name, slide, and confidence improvements.
  - **[ADR-006](adr/ADR-006-storage-drive-sync.md)** — Local **SQLite + per-meeting folder** (cache); **Google Shared Drive via per-user OAuth** as durable source of truth; **company-first** `/<Company>/<YYYY-MM-DD-…>/` layout; write-through upload (no sync client).
  - **[ADR-007](adr/ADR-007-dashboard.md)** — **SwiftUI window in the same app** over SQLite (FTS5 search); list/detail/play/open-in-Drive/re-run-skill. No separate web app.
  - **[ADR-008](adr/ADR-008-claude-auto-trigger.md)** — Headless **`claude -p` chain**, configurable per meeting, **default one-click**; meeting-type routing decides which skills run; `process-meeting`'s human-review gate kept.
  - **[ADR-009](adr/ADR-009-app-architecture-ipc.md)** — **Swift menu-bar app + bundled Python pipeline**, **file-based job queue + JSON status** IPC (simple/observable/resumable); **internal Developer-ID signing** (not App Store) to allow the audio-permission SPI; onboarding wizard for the 4 TCC grants + Drive OAuth.
  - **[ADR-010](adr/ADR-010-privacy-consent.md)** — On-device default; only the team Drive (and opt-in cloud/Claude) leave the Mac; consent metadata + jurisdiction nudge (inform, don't block) + retention controls + **do-not-record defaults for internal events**. Six items flagged for **counsel**.
- **Rationale**: Per the design brief and `RESEARCH.md`; load-bearing claims verified against primary sources (Apple Core Audio docs, ivrit.ai leaderboard, model licenses).
- **Alternatives considered**: Documented per-ADR (e.g., SCK-for-audio rejected for the monthly-nag/Screen-Recording-TCC cost; cloud-ASR-primary rejected — no Hebrew quality win + confidentiality cost; service-account Drive auth rejected in favor of per-user OAuth).
- **Consequences**: Code-switching ASR quality and the no-monthly-nag tap claim are unproven until prototyped; skills in `~/repos/claude-skills` need a coordinated `--package` change; internal signing means maintaining Developer ID + notarization.
