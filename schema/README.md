# `schema/` — the context-package contract (ADR-005)

This directory is **the spine both sides depend on**: the Swift app and the Python pipeline produce
packages that conform to these JSON Schemas, and the downstream Claude skills
(`saventa-summary`, `generate-mom`, `process-meeting`) consume them via their `--package` mode.
The same schemas + the golden fixture are mirrored into `~/repos/claude-skills` so the contract is
testable on both sides (ADR-005).

## Package layout (ADR-005 / ADR-006)

A meeting is a folder. On disk locally it is keyed by meeting id
(`~/Library/Application Support/IN-Meetings/meetings/<id>/`); on Google Drive it is laid out
company-first (`/<Company>/<YYYY-MM-DD-meeting[-N]>/`, slice 6).

```
<meeting>/
  audio_mic.wav          # always (the IN side / in-person room)
  audio_system.wav       # call only — absent for in_person (ADR-011)
  video.mov              # optional — call video, V1 (off at MVP)
  transcript.json        # → transcript.schema.json
  transcript.txt         # human-readable, same content
  context.md             # PRIORS only (ADR-004) — skills must not pull deal narrative from it
  slides_ocr.md          # optional — shared-screen OCR (Phase 4)
  metadata.json          # → metadata.schema.json
```

## Schemas

| File | Validates | Owner (writer) |
|------|-----------|----------------|
| [`transcript.schema.json`](transcript.schema.json) | `transcript.json` | Python pipeline |
| [`metadata.schema.json`](metadata.schema.json) | `metadata.json` | Python pipeline (record-time facts arrive via the job contract, ADR-009) |

The Swift app **reads** the finished package to index it into SQLite (ADR-006) and upload it to Drive
(slice 6); it does not write into the package. Single-writer keeps assembly race-free, and Phase 2's
context assembler — also Python — extends `metadata.json` in place.

## Versioning & forward-compatibility

This contract is **frozen** but designed to **evolve additively**:

- `metadata.json.schema_version` is the contract version (starts at `"1.0"`). Bump it on any change.
- **Consumers MUST ignore unknown fields.** New optional fields are added without a breaking bump.
- Fields that later phases populate are **present but null/empty at MVP**, not absent — so the shape is
  stable from day one. Known-pending producers:
  - **Phase 2** (context assembler): `meeting.title`/`calendar_event_id`, `attendees[]`, `company`,
    `transcription.biased`/`vocabulary_terms_used`, `context.sources`, `speakers[].name`/`email`.
  - **V1** (call video): `recording.video` flips true + a `video.mov` appears.
  - Richer ASR: `utterances[].confidence`.

This is why "freeze the schema first" is safe even though Phase 2 / slice 6 / V1 are still downstream:
the contract anticipates their fields rather than breaking when they land.

## Contract tests

- **Python:** the pipeline's output is `jsonschema`-validated against these files in `pipeline/tests/`.
- **Swift:** `INMeetingsCore` decodes the golden fixture (`fixtures/golden-package/`) into its Codable
  models in `Tests/`.
- The **golden fixture** is the single anchor both sides (and the skills repo) test against.
