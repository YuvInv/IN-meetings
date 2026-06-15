# IN-meetings — Agent Instructions

## Environment
- Primary agent: Claude Code (Anthropic, Opus model family)
- Secondary agent: Codex CLI (OpenAI, GPT-5/Codex model family)
- Both operate on this repo and share this file as the canonical instruction set
- `CLAUDE.md` references this file via `@AGENTS.md` — do not duplicate content there

## Agent Awareness
- **Claude Code**: you have `/codex:review`, `/codex:adversarial-review`, and `/codex:rescue` available. Use them for second opinions on complex changes and pre-merge adversarial reviews on PRs with >200 lines changed.
- **Codex**: the developer also uses Claude Code on this repo. Respect existing `CLAUDE.md` memories and any `/self-review` conventions. Do not contradict architectural decisions made in prior Claude Code sessions unless explicitly asked.
- **Both**: when making significant architectural decisions, document them in `DECISIONS.md` so the other agent can reference them.

## Handoff Protocol
When switching between agents mid-task, the outgoing agent creates or updates `HANDOFF.md` in the project root with:
1. **Current state** — what was accomplished, what files were changed
2. **Open questions** — unresolved decisions or ambiguities
3. **Remaining tasks** — what still needs to be done
4. **Known issues** — bugs found but not yet fixed
5. **Context** — any important context the next agent needs

The incoming agent reads `HANDOFF.md` and `DECISIONS.md` before starting work.

## Code Standards
- TypeScript/JavaScript: ESM imports, strict mode, no `any` types
- Python: type hints, docstrings, `ruff` for formatting
- Commit messages: conventional commits (`feat:`, `fix:`, `chore:`, etc.)
- Run tests before committing
- Focused, atomic commits — one logical change per commit

## Build & Test
- Prototypes (Swift, macOS): `cd prototypes/p3-detect && swift build` · `cd prototypes/p2-capture && swift build`
- ASR benchmark (Python/whisper.cpp): see `pipeline/benchmarks/README.md` (`brew install whisper-cpp ffmpeg`)
- **App (Swift/macOS):** `swift build` (INMeetingsCore SPM package) · `make build-mac` / `make run-mac` /
  `make test` (full app via XcodeGen + xcodebuild). The pipeline needs `whisper-cli` on PATH.
- **Python pipeline:** runs in a **pinned 3.11 venv** (senko needs Python <3.14; system python is 3.14).
  Setup `cd pipeline && uv sync --group dev`; test `.venv/bin/python -m pytest tests/`; lint
  `uvx ruff check in_meetings_pipeline tests`. The app spawns `pipeline/.venv/bin/python` (override:
  `IN_MEETINGS_PYTHON`).

## Project

**IN-meetings** — a no-bot, native macOS meeting recorder + Hebrew transcription pipeline for IN Venture (early-stage Israeli VC, ~5 users). Replaces Timeless. The edge is **context injection before transcription** (Google Calendar + Saventa CRM + Dealigence → ASR biasing vocabulary) and a per-meeting **context package** consumed by the existing Claude skill stack (`saventa-summary`, `generate-mom`, `enrich-company` at `~/repos/claude-skills/`).

Hard constraints (from the design brief, non-negotiable):
- macOS native only, **no meeting bots**, invisible to other participants
- Apple Silicon target; team floor: macOS 26 (Tahoe), M3/16GB
- **No virtual audio drivers** (no BlackHole/Loopback) — ScreenCaptureKit + Core Audio process taps only
- Confidential founder/deal conversations — on-device processing by default; any cloud ASR is a deliberate, documented tradeoff
- Output must be Claude-skill-ready (the context package is the stable contract)

## Current Phase

**MVP spine complete + merged to `main`** (Phase-0 prototypes + Phase-1 MVP + Phase-2 calendar context +
App-UX slice 1). The app runs end-to-end: detect → dual-track capture → on-device Hebrew transcription
(post-correction + Silero VAD) → senko diarization → context package → Drive backup → Liquid Glass
dashboard. **Now executing the "Road to a team-ready v1" roadmap** (`IMPLEMENTATION_PLAN.md` → that
section): **P0** installable & trustworthy (hybrid Dock + menu-bar app shell, Developer-ID
sign/notarize/.dmg, launch-at-login, onboarding/TCC wizard, reliability pass) → **P1** value loop + video
→ **P2** polish. **Read `HANDOFF.md` + `DECISIONS.md` before starting.** P4 (in-person diarization) still
pending. Stack: Swift/SwiftUI **hybrid Dock + menu-bar** app + Python transcription/context/Drive pipeline
(pinned 3.11 venv).

## Architecture
- Document significant decisions in `DECISIONS.md`; design-phase decisions live in `adr/` and are mirrored as one-liners in `DECISIONS.md`
- Prefer composition over inheritance
- Keep functions small and focused

## Review Checklist (both agents)
Before marking work as done:
- [ ] All tests pass
- [ ] No lint errors
- [ ] `HANDOFF.md` updated if mid-task
- [ ] `DECISIONS.md` updated if an architectural choice was made
- [ ] Changes are committed with conventional commit messages
