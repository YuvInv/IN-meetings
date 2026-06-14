# Agent Handoff — IN-meetings

<!--
Rewritten at every handoff. The incoming agent reads this + DECISIONS.md before starting.
Keep it short: last state, next steps, gotchas. History lives in git log.
-->

## Outgoing Agent
Claude Code · 2026-06-14

## Current State
**MVP Phase 1 spine + the context-package contract are in place.** Slices **1–4c + mila harvests
H0/H1/H3 are merged to `main`** (PRs #1–#3). **Slice 5 (context package + SQLite index) was implemented
this session** on a clean `main` (**uncommitted** — see "Next"). End to end now:
detect → dual-track record → on-device Hebrew transcription → diarization → **packaged to the frozen
schema + indexed in SQLite**.

### This session (2026-06-14): slice 5 — freeze the contract + SQLite index (DECISIONS 2026-06-14)
Built in 5 verified steps; all green (**Python 17, Swift 21, `make build-mac`, ruff clean**):
- **Schema frozen** — `schema/transcript.schema.json` + `schema/metadata.schema.json` (JSON Schema
  2020-12, forward-compatible) + `schema/README.md` (layout + versioning + who-writes-what).
- **Pipeline emits the full package** — `transcript.json` aligned to ADR-005 (`utterances[]`, seconds,
  `speaker_id`, `confidence`, provenance `engine`/`model_revision`/`biased`); new
  `pipeline/in_meetings_pipeline/metadata.py` writes `metadata.json`; `job.py` carries record-time facts;
  a `"packaging"` status was added before the package write.
- **Golden fixture + contract tests** — `schema/fixtures/golden-package/` is the cross-language anchor;
  `pipeline/tests/test_contract.py` `jsonschema`-validates the schemas, the fixture, AND the pipeline's
  actual emitted output. (`jsonschema` added as a dev dep.)
- **Swift SQLite index (GRDB)** — `Sources/INMeetingsCore/Store/{ContextPackage,MeetingStore}.swift`:
  Codable models decode the fixture; `MeetingStore.indexPackage(at:)` upserts a `meeting` row (idempotent).
  GRDB is the **first dependency** in the (previously dependency-free) Core package, pinned to 6.x.
- **Wiring** — `JobBridge.enqueue` writes the extended `job.json` (via a pure, tested `makeJob`); on
  pipeline `"done"` it indexes the package into SQLite. `RecordingController` passes start/end + the
  detected call app to `enqueue`.

Slices 1–4c + H0/H1/H3 (all merged, all live-verified) — unchanged from the prior handoff (git log).

## Next — START HERE
- **⚠️ Commit slice 5** — it's uncommitted on `main`. Branch (`feat/slice-5-context-package`) → conventional
  commits → PR, per the project's PR workflow (PRs #1–#3).
- **⏳ LIVE-VERIFY slice 5** (the one thing not done): record a real meeting → confirm the folder gets a
  schema-valid `transcript.json` + `metadata.json`, `pipeline.log` shows the `"packaging"` phase, and a row
  lands in `~/Library/Application Support/IN Meetings/meetings.db`. The unit/contract layer is green; the
  end-to-end record → package → index path is untested live.
- **Slice 6 — Drive sync** (next core-spine step): per-user OAuth, company-first layout (ADR-006); upload
  the package and fill the `driveFolderId` / `syncState` columns the index already carries.
- Then **Phase 2** (context assembler + biasing — the differentiator). Additive harvests (V1 call video,
  V2 auto-stop, H4 dashboard, H2 Sparkle) stay off the spine's critical path.
- **Skills `--package` adapter** (ADR-005 part 2, Phase 3): a coordinated change in `~/repos/claude-skills`
  — mirror `schema/fixtures/golden-package/` there as the cross-repo contract test.

## Gotchas (verified)
- **@Observable + `lazy`**: a `lazy var` on an `@Observable @MainActor` class won't compile (the macro makes
  it computed) — mark non-observed stored props `@ObservationIgnored` (as `JobBridge.store` does). Pure
  helpers called from tests off the main actor need `nonisolated` (as `JobBridge.makeJob` does).
- **Pipeline tests need the package on the path**: run `pytest` from `pipeline/` (or set
  `PYTHONPATH=pipeline`), else `in_meetings_pipeline` won't import.
- **`metadata.py` reads WAV duration/sample-rate via soundfile**, not stdlib `wave` (capture tracks are
  float32, which `wave` rejects) — so Swift needn't send them.
- (carried) **senko needs Python <3.14** → pinned 3.11 venv (`pipeline/.venv`); **TCC grant needs a
  relaunch** (mic + System Audio Recording); tap write is interleaved float32 (pin `AVAudioFile` to the tap
  format or `write` fails −50); **pipeline is spawned, not compiled in** (editing `pipeline/` needs no app
  rebuild); model download (H1) → `IN_MEETINGS_MODEL`.

## Open / follow-ups
- (carried) **⏳ multi-party-call diarization quality** untested on a real call (MVP-accepted) — review the
  per-meeting `pipeline.log` once real calls run.
- SourceKit may show stale "Cannot find type MeetingStore" squiggles until it reindexes the new GRDB dep —
  cosmetic only; `swift test` + `make build-mac` are green.
- (carried) pyannote fallback not wired; onboarding TCC wizard minimal; Soniox fallback / auto-trigger
  default / counsel review of ADR-010.

## Context
- Env: macOS 26 / M3+/16GB. Package layout = ADR-005; local cache under `~/Library/Application Support/IN
  Meetings/` (`Recordings/`, `Models/`, `meetings.db`); Drive (slice 6) = per-user OAuth, company-first.
- Pipeline dev paths are hardcoded in `JobBridge` (overridable via `IN_MEETINGS_PIPELINE_DIR` /
  `IN_MEETINGS_PYTHON` / `IN_MEETINGS_MODEL`); Phase 5 bundles the pipeline + a sealed env.
- Downstream skills call the Timeless API directly today — the context package is a NEW contract (ADR-005).
