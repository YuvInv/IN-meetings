# ADR-005 — Context package contract & Claude-skill integration

**Status:** Proposed · **Date:** 2026-06-11 · **Deciders:** Yuval (review)
**Brief item:** F · **Research:** `docs/notes/skill-contracts.md` (actual skill inputs)

## Context

The context package is the stable contract between this app and the Claude skill stack — the payoff of
the whole project. Critical finding from reading the actual skills: **`saventa-summary`, `generate-mom`,
and `process-meeting` do NOT read files today — they call the Timeless API directly** (transcript JSON
with `items[]` of text/start/end/speaker_id + `speakers[]`, AI summary as HTML, `language` field). So
the package is a **new input contract** for them. The skills also load `vc-context/` first and enforce
rules that constrain the package (e.g., `saventa-summary` filters internal-domain emails and treats the
transcript as ground truth; `generate-mom` sanity-checks numbers and wants confidence signals).

## Decision

**1. Freeze the package schema as the contract** (matches the brief, with the fields the skills
actually need):

```
/<Company>/<YYYY-MM-DD-meeting[-N]>/
  audio_mic.wav
  audio_system.wav
  video.mov                # optional
  transcript.json
  transcript.txt
  context.md               # PRIORS only (ADR-004)
  slides_ocr.md            # optional
  metadata.json
```

`transcript.json` (ADR-003): `language`, `engine`, `model_revision`, `biased`, `utterances[]`
`{text,start,end,speaker_id,confidence}`, `speakers[]` `{id,name?,email?,side:internal|external}`.

`metadata.json` (minimum):
- `meeting`: `{title, start, end}` ISO-8601 (**calendar-authoritative** when matched), `calendar_event_id`
- `attendees[]`: `{name, email, side: internal|external, matched_crm_contact_id?}`
- `company`: `{name, sevanta_deal_id?, dealigence_id?, matched: bool}` (null/`matched:false` when new)
- `recording`: `{durations, tracks, sample_rate, capture_source_app, video: bool}`
- `transcription`: `{engine, model_revision, language, biased, vocabulary_terms_used}`
- `context`: `{sources: {calendar, saventa, dealigence} each ok|empty|error}`
- `consent`: `{status: verbal|calendar-notice|none|internal, jurisdiction_hint?}` (ADR-010)

**2. Add a local-package input mode to the consuming skills** (small, additive change — extraction
logic is unchanged, only the fetch step is replaced):
- `saventa-summary`, `generate-mom`, `process-meeting` gain a **`--package <path>`** (or "use this
  local meeting folder") mode that reads `transcript.json` / `transcript.txt` / `metadata.json` /
  `context.md` instead of calling Timeless. The Timeless path stays for backward compatibility.
- A tiny **shared adapter** (`package → the in-memory shape the skills already use`) so the change to
  each skill is one branch at the top. This lives in the skills repo, mirrored in this repo's
  `docs/notes/skill-contracts.md` as the spec.
- `enrich-company` needs no transcript — it just reads `company.name` / `sevanta_deal_id` from
  `metadata.json` for chaining (ADR-008).
- `create-snapshot` is unaffected — it consumes the MoM `.docx`, which `generate-mom` still produces.

**3. Skill improvements this richer input enables** (propose to the skills, not required for v1):
- **Better Hebrew-name handling:** pass calendar attendee name spellings (both scripts) so the MoM/
  summary use the *correct* romanization instead of guessing from audio.
- **Slide context in the MoM:** when `slides_ocr.md` exists, `generate-mom` can fold shared-screen
  numbers/claims into the analysis — context pure audio loses.
- **Confidence-aware number sanity-checks:** `transcript.json` confidence lets critical-analysis flag
  low-confidence figures (the מיליון/מיליארד, $1.5M/$15M class of errors) instead of guessing.
- **Pre-resolved CRM match:** `metadata.json.company.sevanta_deal_id` lets `process-meeting` skip the
  fuzzy CRM search and its ambiguity branch when we already matched the deal.
- **The internal/external split** is already computed (ADR-004), so `saventa-summary` doesn't have to
  re-derive the host domain.

**4. Preserve the priors/content wall.** `context.md` is labeled PRIORS; the skills must not pull deal
narrative from it. This is stated in the package (`context.md` header) and in the skill spec.

## Options considered

| Option | Why not |
|--------|---------|
| Make the recorder emit Timeless-API-shaped JSON and have skills call a local mock server | Heavier and indirect; a `--package` file mode is simpler and observable. |
| Re-implement the skills inside this app | Duplicates logic the user maintains in `~/repos/claude-skills`; the skills are the product surface — integrate, don't fork. |
| One mega-skill that does everything from the package | Loses the composability the user already relies on (summary vs MoM vs CRM vs enrich are separate, chosen per meeting). |

## Consequences

- **Good:** the package is a clean, durable contract; the skills change minimally and keep their
  Timeless compatibility; the richer fields unlock real quality wins (names, slides, confidence) the
  Timeless path never had.
- **Costs/risks:** the skills live in a separate repo (`~/repos/claude-skills`) — changes there are
  out of scope for this repo's code but **in scope for this design**; they must be coordinated. The
  schema must be versioned (`metadata.json.schema_version`) so future changes don't break skills. A
  golden-package fixture should live in both repos so the contract is testable on each side.
