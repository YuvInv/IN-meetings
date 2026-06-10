# Downstream Skill Contracts — what the context package must satisfy

> Design input for ADR-005. Compiled 2026-06-10 from the actual skill definitions.
> Sources: `~/repos/claude-skills/` (generate-mom, process-meeting, vc-context, create-snapshot, timeless)
> and the Claude desktop skills plugin (saventa-summary, timeless-access).

## How meeting data is consumed TODAY (Timeless era)

All meeting-consuming skills call the **Timeless API directly** — none read local files:

- `GET /api/v1/spaces/meeting/?include=owned|shared&status=COMPLETED` → meeting list
  (`uuid`, `name`, `start_ts`, `conversation_uuid`, `host_uuid`, participants)
- `GET /api/v1/spaces/{uuid}/` → `artifacts[]` (AI summary as HTML), `conversations[]`
- `GET /api/v1/conversation/{uuid}/transcript/` → `items[]` (`text`, `start_time`, `end_time`,
  `speaker_id`) + `speakers[]` (id → name/email) + `language` (`"he"`/`"en"`)
- `GET /api/v1/conversation/{uuid}/recording/` → signed media URL

**Implication:** the per-meeting context package is a NEW input contract. Each consuming skill
needs a "local package path" input mode (small change — the extraction logic is unchanged;
only the fetch step is replaced).

## Per-skill requirements on the package

### saventa-summary (short plain-text Saventa note)
- Transcript with **speaker names** (not just ids) — treats transcript as ground truth over any summary.
- **Participant metadata with emails**, and a way to tell internal (IN Venture) from company-side:
  it filters out internal-domain emails and attaches founder emails to Team lines.
  → package `metadata.json` must carry attendees as `{name, email, role: internal|external}`
  (calendar organizer domain = internal domain).
- **Authoritative meeting date/time** (calendar event start preferred over recording timestamp).
- Optional: AI summary artifact(s) — used alongside transcript; transcript wins conflicts.
- Hard rule it enforces: deal narrative comes ONLY from the call; calendar/email data is for
  identity/logistics only. Package should keep `context.md` (CRM/Dealigence priors) clearly
  separated from the transcript so the skill can respect that wall.

### generate-mom (.docx MoM)
- Same transcript shape (timestamps + speaker attribution) + AI summary as input.
- Loads `vc-context/` first (critical-analysis.md Rule 3: sanity-check numbers — מיליון vs
  מיליארד, $1.5M vs $15M) → package transcript should preserve confidence scores so the skill
  can flag low-confidence numbers.
- Template at `~/repos/openclaw-skills/templates/MoM-template.docx`; output to `/tmp/mom-output/`.
- Opportunity (brief asks to propose): slide/screen-share OCR (`slides_ocr.md`) as added context;
  better Hebrew-name romanization using calendar-attendee spellings.

### process-meeting (CRM upload)
- Extracts companyName, founders[], market, problem, solution, traction, fundingHistory,
  meetingParticipants[] from transcript + summary → same inputs as above.
- CRM matching needs **company name** early → package `metadata.json` should carry the
  pre-resolved company + Sevanta deal id when the context assembler matched one (saves the
  skill a fuzzy search and removes ambiguity).
- Gotchas live in the skill (form-encoded POSTs, dd-mm-yyyy dates, label/dbname duality) — not
  package concerns.

### create-snapshot (one-pager Firestore write)
- Consumes the MoM .docx downstream — unaffected if generate-mom's output contract holds.
- Uses Dealigence avatars by founder name → package metadata carrying canonical founder names
  (from calendar) improves match quality.

### enrich-company
- Purely API-driven (company name / CRM id) — package only needs to provide the company name
  and (ideally) the Sevanta CompanyID in `metadata.json` for chaining.

## Minimum viable package contract (consolidated)

```
/<Company>/<YYYY-MM-DD-meeting>/
  audio_mic.<ext>            # user side
  audio_system.<ext>         # remote participants
  video.<ext>                # optional
  transcript.json            # utterances: {text, start, end, speaker_id, confidence};
                             # speakers: {id, name, email?, side: internal|external}; language
  transcript.txt             # clean readable text with speaker names
  context.md                 # calendar + Saventa + Dealigence priors (clearly marked as priors)
  slides_ocr.md              # optional screen-share extraction
  metadata.json              # see below
```

`metadata.json` minimum fields:
- `meeting`: title, start/end (ISO 8601, calendar-authoritative), calendar_event_id
- `attendees[]`: {name, email, side: internal|external, matched_crm_contact_id?}
- `company`: {name, sevanta_deal_id?, dealigence_id?} (null when unmatched)
- `recording`: durations, track files, sample rates, capture source app
- `transcription`: engine, model, language, biasing vocabulary used

## Security note (flag to user)

`timeless-access` SKILL.md (desktop plugin copy) embeds a live `TIMELESS_ACCESS_TOKEN`
fallback value in plaintext — should be rotated/removed independent of this project.
