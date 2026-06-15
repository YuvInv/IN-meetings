# ADR-010 — Privacy & consent posture

> **⚠️ Amended 2026-06-14** (see [DECISIONS.md](../DECISIONS.md)): **call video ON by default** materially changes this posture — every call is filmed, so revisit consent/retention defaults + the do-not-record list (**counsel review required before rollout**). A retention/size cap ships with video in **P1**.

**Status:** Proposed · **Date:** 2026-06-11 · **Deciders:** Yuval (review) + **counsel (required)**
**Brief item:** Phase-1 consent research, Phase-2 privacy · **Research:** RESEARCH.md §5

> **This ADR records design considerations, not legal advice.** The flagged items must be reviewed by
> counsel before rollout. The brief explicitly says: do not treat consent as settled law.

## Context

These are confidential founder/deal conversations. The product is silent local capture, which bypasses
every platform recording notice. Research findings that shape the posture:

- **Israel (home) is one-party consent** — a participant may record silently (unchanged as of mid-2026).
- **Amendment 13 (PPL, effective 2025-08-14)** regulates the stored corpus: a meetings library with
  speaker identities is plausibly a regulated "database"; founder financials/health/legal can be
  "especially sensitive". Fines, statutory damages, DPO/notice/security duties.
- **Counterparties:** ~11–12 US **all-party** states (CA/WA/FL); CIPA = $5,000/violation, driving live
  litigation (*In re Otter.AI*). EU/GDPR: recording identifiable people is processing (legitimate
  interest + notice; DPIA likely). UK: risk is in sharing/processing (Drive/Claude).
- **Industry norm** (Granola et al.): silent by default + an *optional* disclosure helper + retention
  controls. No mainstream local tool blocks recording. Granola's auto-consent works on Zoom-macOS only
  (**Meet paused** — and Meet is IN Venture's primary platform).
- macOS shows a **local purple recording indicator** (recordist-only, but visible if they screen-share
  the menu bar).

## Decision

**On-device by default; match the industry norm (inform, don't block) with strong retention controls;
default to NOT recording internal meetings; surface jurisdiction nudges; keep auditable consent
metadata. Defer the legal determinations to counsel.**

**Data flow (what leaves the Mac):**
- Default: **nothing leaves the Mac except to the team Google Drive** (ADR-006). ASR/diarization/context
  assembly are all on-device.
- **Opt-in, per-meeting, logged** exits: cloud ASR fallback (Soniox/Deepgram — ADR-003) and the Claude
  trigger (`claude -p` — ADR-008). Each records in `metadata.json` what was sent and where.
- The context assembler's MCP calls (Calendar/Saventa/Dealigence) use the user's existing connectors;
  no meeting audio is sent to them.

**Consent features (norm-matching, all configurable):**
1. **Per-meeting `consent.status`** in metadata: `verbal | calendar-notice | none | internal`, plus a
   `jurisdiction_hint` derived from attendee email domains / calendar timezones. Cheap, auditable.
2. **Jurisdiction-aware nudge** (inform, never block): if attendees resolve to US all-party states or
   EU domains, the banner suggests a one-line verbal disclosure. 
3. **Verbal-disclosure capture:** optional one-tap "I asked, they're OK" that timestamps the affirmation
   against the transcript (Granola's recommended best practice = contemporaneous evidence).
4. **Calendar-invite boilerplate** snippet the team can add to invites (the GDPR-friendly async notice).
5. **Meet-compatible disclosure** is a differentiator opportunity (even Granola lacks it) — a later
   enhancement, not v1.

**Retention controls (directly responsive to Amendment 13 / GDPR minimization):**
- Configurable **auto-delete of raw audio** after successful transcription (transcript retained) —
  Granola precedent; default **on** for the system/remote track, configurable for mic.
- Transcript/package retention window (e.g., delete after N months) — configurable, default off
  pending counsel.
- **Per-meeting purge** action in the dashboard (local + Drive) — "delete everything for this meeting".

**Do-not-record defaults (Israeli employment-privacy exposure is higher for *internal* recordings):**
- All-internal-attendee events (every attendee on the IN Venture domain), and calendar events matching
  keywords (1-on-1, HR, review, comp, board-confidential) → **default to not recording / not arming**;
  the user can override explicitly.

**Access control:** least-privilege Drive sharing (Shared Drive, no org-wide links); per-user OAuth
gives per-user attribution; the recordings corpus is treated as sensitive (possible PPL "database").

**Onboarding honesty:** explain the local purple indicator (it supports the no-bot trust story but is
visible on screen-share); state that the team is responsible for obtaining consent where required.

## Items requiring counsel (do not ship without review)
1. Is the meetings-recordings corpus a regulated/registrable **database** under Amendment 13; is a **DPO**
   needed? 2. **EU** lawful basis + whether a **DPIA** is required for recording EU founders/LPs.
3. **CIPA** exposure when recording CA/WA/FL counterparties from Israel, and whether disclosure language
   mitigates. 4. **Internal-employee** recording policy + written notice. 5. **Retention schedule**.
6. What **consent evidence** to store and for how long.

## Options considered

| Option | Why not |
|--------|---------|
| Block recording without all-party consent | No mainstream tool does this; brittle; not how one-party-consent practice works. Inform, don't enforce. |
| Silent, no consent features at all | Out of step with norm and with the live litigation risk; cheap to add metadata + nudges. |
| Record internal meetings by default | Highest Israeli legal exposure (employment privacy); default off. |
| Cloud-first processing | Violates the confidentiality-first constraint; on-device default is the whole point. |

## Consequences

- **Good:** confidentiality-first; matches the industry norm (and can exceed it later via Meet
  disclosure); retention + do-not-record defaults directly address the real Amendment-13/employment
  risks; everything auditable.
- **Costs/risks:** the legal questions are genuinely unsettled (conflict-of-laws for cross-border calls)
  — **must** go to counsel; jurisdiction inference from email domains is heuristic; auto-deleting raw
  audio trades away the ability to re-transcribe later (make it configurable, warn in UI). The purple
  indicator can't be hidden — set expectations rather than fight it.
