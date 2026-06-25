# INV Meetings

> A no-bot, native macOS meeting recorder with on-device Hebrew transcription and a per-meeting context
> package — built for [IN Venture](https://in-venture.com).

INV Meetings records your video calls and in-person meetings **without joining as a bot** and **without any
virtual audio driver**. It captures audio (and optionally screen video) straight from macOS, transcribes
Hebrew on-device, separates who-said-what, and assembles a tidy per-meeting package — transcript, summary,
and recording — that you can keep locally or back up to Google Drive. Confidential founder and deal
conversations never have to leave the machine.

## Features

- **Automatic call detection** — notices when a call starts (Zoom/Meet/Teams/etc.) via Core Audio process
  I/O and offers to record; auto-stops with a visible countdown when the call ends.
- **Dual-track capture, no virtual drivers** — microphone + system audio via ScreenCaptureKit and Core
  Audio process taps. Optional **screen video** captured through a single ScreenCaptureKit stream (one
  clock, so audio/video stay in sync).
- **On-device Hebrew ASR** — local Whisper (ivrit) with deterministic post-correction and Silero VAD (no
  silence hallucination). Nothing is sent to the cloud for transcription.
- **Speaker diarization** — senko-based who-said-what, with one-tap manual speaker naming in the app.
- **Calendar context injection** — Google Calendar enriches each meeting (time, attendees, internal vs.
  external) and biases the transcription vocabulary.
- **In-app summaries** — a finished meeting auto-runs a bundled summary recipe; create your own recipes and
  run several per meeting, right from the meeting page.
- **Optional Google Drive backup** — connect an account, pick a folder, and each meeting lands in **one
  folder named with its timestamp** containing the video, transcript, and summary.
- **Liquid Glass dashboard** — a native macOS 26 dashboard for browsing meetings, playing the recording,
  reading the synced transcript, and managing summaries.

## Privacy & constraints

- macOS-native only, **no meeting bots**, invisible to other participants.
- **No virtual audio drivers** (no BlackHole/Loopback) — ScreenCaptureKit + Core Audio process taps only.
- **On-device by default.** Transcription, diarization, and summaries run locally; Drive backup is opt-in.

## Requirements

- macOS 26 (Tahoe) or later, **Apple Silicon** (M3 / 16 GB is the team floor).
- [`whisper-cli`](https://github.com/ggerganov/whisper.cpp) and `ffmpeg` on `PATH` —
  `brew install whisper-cpp ffmpeg`.
- Python 3.11 for the transcription pipeline (the app spawns a pinned venv — see below).
- Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to build the app.

## Quick start

```bash
# Build and run the macOS app
make build-mac        # build (auto-generates the .xcodeproj from project.yml)
make run-mac          # launch it
make test             # Swift package unit tests (INMeetingsCore)
make help             # list every target

# Set up the Python transcription pipeline (pinned 3.11 venv)
cd pipeline
uv sync --group dev
.venv/bin/python -m pytest tests/      # run the pipeline tests
```

The app spawns `pipeline/.venv/bin/python` (override with the `IN_MEETINGS_PYTHON` env var).

## How it works

```
detect call  →  dual-track capture (mic + system, optional screen video)
            →  on-device Hebrew transcription (post-correction + Silero VAD)
            →  senko diarization  →  context package (transcript + metadata + calendar context)
            →  optional Google Drive backup  →  Liquid Glass dashboard + summaries
```

## Project structure

| Path | What's there |
|------|--------------|
| `Sources/INMeetingsCore/` | Swift package — the testable core (capture, detection, Drive, store, summaries) |
| `Apps/INMeetings/` | The macOS app target (SwiftUI, hybrid Dock + menu-bar); generated from `project.yml` |
| `Tests/INMeetingsCoreTests/` | Swift unit tests |
| `pipeline/` | Python transcription/context/Drive pipeline + tests + benchmarks |
| `schema/` | The context-package contract (JSON schemas + golden fixture) |
| `adr/` | Architecture Decision Records |
| `prototypes/` | Phase-0 de-risk prototypes (capture, detection) |
| `docs/` | Distribution runbook, research notes |

## Documentation

- [`DESIGN.md`](DESIGN.md) — architecture spine (ties the ADRs together)
- [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) — live, ordered priorities ("Road to a team-ready v1")
- [`DECISIONS.md`](DECISIONS.md) — append-only log of architectural decisions
- [`adr/README.md`](adr/README.md) — index of Architecture Decision Records
- [`schema/README.md`](schema/README.md) — the context-package contract
- [`RESEARCH.md`](RESEARCH.md) — Hebrew ASR / capture-API / market research backing the design

## Contributing

This repo is worked by both **Claude Code** and **Codex CLI**. The shared, canonical instruction set —
code standards, build/test commands, and the handoff protocol — lives in [`AGENTS.md`](AGENTS.md). Read it
before making changes.

## Licensing

Internal IN Venture tool. Third-party code adapted into this project (e.g. Mila, Apache-2.0) is credited in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and [`NOTICE`](NOTICE).
