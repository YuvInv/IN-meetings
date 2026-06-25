# ADR-006 — Storage, backend & Google Drive sync

> **⚠️ Amended 2026-06-14** (see [DECISIONS.md](../DECISIONS.md)): Drive sync is **Swift-owned** (moved out of the Python pipeline) with a **per-user dynamic backup location** (each user connects their account + picks the Shared Drive). A **Drive folder picker** + a retention/size cap are **P1**.
>
> **⚠️ Amended 2026-06-25** (see [DECISIONS.md](../DECISIONS.md)): the per-meeting Drive layout is now a **flat folder named with the meeting timestamp** directly under the chosen location (no `<Company>/` tier), holding only **the recording + `transcript.txt` + `summary.md`**. Drive is a human-facing share, not a full context-package mirror — the complete package stays local. Supersedes the "Decision" section's company-first layout and "What syncs" list below.

**Status:** Proposed · **Date:** 2026-06-11 · **Deciders:** Yuval (review)
**Brief item:** E · **Confirmed:** Drive auth = per-user OAuth (user decision)

## Context

Keep it simple, local-first, but make the team Drive the durable source of truth so meetings are
shared across the 5-person team and survive any one Mac. The user has confirmed **per-user OAuth** for
Drive (each teammate authorizes once; no Workspace-admin service-account setup).

## Decision

**Local: SQLite metadata index + per-meeting folder on disk.**
- One SQLite DB (`~/Library/Application Support/IN-Meetings/meetings.db`) indexing every meeting:
  id, company, title, start/end, attendees, paths, durations, transcription status, drive file ids,
  skill-run results, consent status, sync state. This powers the dashboard (ADR-007) — no heavier
  store needed for ~5 users.
- Per-meeting folder under a local root (`~/Library/Application Support/IN-Meetings/meetings/<id>/`)
  holding the context package (ADR-005). **Local disk is a cache**; Drive is durable.

**Durable: Google Drive shared drive, per-user OAuth.**
- A **Shared Drive** ("IN Meetings") that all teammates can access — folders organized
  **`/<Company>/<YYYY-MM-DD-meeting[-N]>/`** (the package layout). Company-first, then date, so a
  partner can open a company and see every meeting chronologically.
- **Auth:** per-user OAuth (Drive scope), token in the macOS Keychain. Each teammate's uploads are
  attributed to them (clean audit trail) — which also serves the consent/retention posture (ADR-010).
- **Sync model:** after the pipeline writes the package locally, upload the folder to Drive and store
  the Drive file/folder ids in SQLite. Drive is **write-through, not a live mirror** — we control
  uploads (no third-party sync client, no driver). Re-runs/skill outputs are re-uploaded in place.
- **Conflict/dup handling:** meeting id is deterministic (date + company + sequence); the `-N` suffix
  disambiguates same-day repeats. Idempotent upload (check existing Drive ids before re-creating).

**What syncs:** transcript.json/.txt, context.md, slides_ocr.md, metadata.json, and skill outputs
**always**; **audio** per retention policy (ADR-010 — may auto-delete raw audio after transcription);
**video** only if captured. Large media upload is chunked/resumable and runs in the background.

## Options considered

| Option | Why not |
|--------|---------|
| Service-account Drive auth | Needs Workspace admin + domain-wide delegation; a single high-value credential; no per-user attribution. User chose per-user OAuth. |
| Google Drive desktop client to auto-sync a local folder | A sync client/driver-ish dependency we don't control; conflict behavior is opaque; explicit API upload is simpler and auditable. |
| Postgres / a server backend | Massive over-engineering for 5 users; the brief says don't over-engineer. SQLite + Drive is enough. |
| Per-user My Drive (not a Shared Drive) | Files would be owned by individuals and lost on offboarding; a Shared Drive keeps team ownership. |
| Date-first folder layout | Company-first matches how a VC thinks (per-company deal history); date-first scatters a company's meetings. |

## Consequences

- **Good:** dead-simple, local-first, resilient; team-shared via a Shared Drive with per-user
  attribution; no admin setup, no sync client, no driver; company-first layout matches deal workflow.
- **Costs/risks:** per-user OAuth means each teammate does a one-time consent (onboarding handles it);
  token refresh/expiry handling needed (Keychain + refresh token); a Shared Drive requires the team to
  be on Google Workspace (they are). Background upload of large WAV/video needs resumable logic and a
  retry queue (network drops). Retention policy (ADR-010) decides whether raw audio ever leaves the Mac.
