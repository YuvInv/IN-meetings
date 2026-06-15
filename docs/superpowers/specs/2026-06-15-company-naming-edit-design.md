# Company naming + edit — Design Spec

**Date:** 2026-06-15 · **Status:** approved (Yuval) → ready for implementation plan
**Roadmap:** P1, "Road to a team-ready v1" (gap #2). **Branch:** `feat/company-naming`

## Problem
Every meeting's headline is the company. Today it's derived **only** from the dominant external
email domain on the matched calendar event (`context_assembler.resolve_company`). When there's no
external attendee, no calendar match, or a fetch failure, the dashboard shows **"Unknown company"**
with **no way to fix it** — there is no edit UI and no `MeetingStore` update path. The "Needs linking"
bucket surfaces these but clicking does nothing.

## Goals
1. Catch more companies automatically (add a title-based fallback to the existing domain inference).
2. Let the user **set/rename** a meeting's company from the dashboard, and have it **stick** —
   including in the package the Claude skills / CRM auto-trigger will later consume.

## Locked decisions (from brainstorming, 2026-06-15)
- **Propagation:** a rename updates the local index **and** the meeting's `metadata.json`, and
  **re-uploads that file to Drive** (so the package stays correct). The Drive **folder is not moved**
  (it stays `<originalCompany>/<meetingId>/`; only the file content changes).
- **Inference depth:** calendar **domain + title fallback**. **No transcript-content scanning**
  (Hebrew/English NER is noisy; the manual edit is the reliable fallback).
- **Who writes `metadata.json`:** **Swift**, in-process, single-field — a deliberate, documented
  exception to "Python is the single writer of the package" (ADR-009 / slice-5). Rationale: this is a
  serialized, post-pipeline, one-field user edit, not concurrent assembly; doing it in-process keeps
  the rename snappy and avoids coupling it to spawning the Python venv. Guarded by disabling the edit
  while a meeting is still processing.

---

## Design

### 1. Inference — Python (`pipeline/in_meetings_pipeline/context_assembler.py`)
`resolve_company(attendees, title)` gains a **title fallback**, used only when no external non-public
domain resolves:

1. **Domain (unchanged):** dominant external non-public email domain → `Company(name, source="domain")`.
2. **Title fallback (new):** parse `title` for the external party. Conservative, in order:
   - **"meets" separators** — split on ` <> `, ` <-> `, ` / `, ` | `, ` – ` (en-dash), ` - `
     (spaced hyphen), ` x ` (e.g. "IN Venture x Acme"). Take the segment that is **not** internal
     (see internal stoplist). If exactly one non-internal segment remains → that's the company.
   - **"with/to/for" prefix** — `^(intro|call|meeting|sync|chat)\b.*\b(with|to|for)\s+(.+)$` → group 3;
     and `^(.+?)\s+(intro|call|meeting)\b` → group 1.
   - **Guards:** trim; reject if the candidate is in a **generic stoplist** (`weekly sync`, `standup`,
     `1:1`, `catch up`, `team`, `internal`, `sync`, `check-in`, …), is < 2 chars, or is purely the
     internal org. **Internal stoplist:** the fund name + variants (`IN Venture`, `IN-Venture`, `INV`,
     `IN`) plus the **internal attendees' names** (those already in `attendees` with `side=="internal"`) — no new params needed.
   - Match → `Company(name=candidate, source="title")`. No match → `None`.
3. No company at all → `None` (metadata `company` stays null → dashboard "Unknown" / Needs-linking).

**`source` field (new, additive):** `company.source ∈ {"domain","title","user",null}`. Set by inference
("domain"/"title") and by the user edit ("user"). Provenance + lets a future re-transcribe avoid
clobbering a user edit. No behavior depends on it yet beyond being written/preserved.

### 2. Schema — `schema/metadata.schema.json` (+ `schema/fixtures/golden-package/metadata.json`)
Add optional `company.source` (string, nullable). **Additive, no `schema_version` bump** (slice-5
reserved this pattern; Swift's decoder ignores unknown keys). Update the golden fixture to carry a
`source` and keep the both-sides contract test green.

### 3. Store — `Sources/INMeetingsCore/Store/MeetingStore.swift`
Add a targeted update (mirrors `setSyncState`):
```swift
public func updateCompany(id: String, name: String?) throws {
    try dbQueue.write { db in
        try db.execute(sql: "UPDATE meeting SET company = ? WHERE id = ?", arguments: [name, id])
    }
}
```
No schema migration (the `company` column already exists, nullable).

### 4. CompanyEditor — new `Sources/INMeetingsCore/Store/CompanyEditor.swift`
One responsibility: apply a user company edit across all three stores, in order:
1. **`metadata.json` (disk):** read the meeting folder's `metadata.json` as `[String: Any]`
   (`JSONSerialization`), set `company` (creating the object if it was null) to
   `{ name, source: "user", matched: <preserved or false>, sevanta_deal_id: <preserved>, dealigence_id:
   <preserved> }` — **preserving every other top-level key and the other company keys** — write back
   atomically. Dict-level edit (not Codable round-trip) so unknown/future fields survive.
2. **SQLite:** `store.updateCompany(id:, name:)`.
3. **Drive (best-effort):** if the `MeetingRecord.driveFolderId != nil`, re-upload `metadata.json` to
   that folder, overwriting the existing file (Drive `files.update` by id, or upload + replace). Failure
   is **non-blocking** — the local edit holds; log + leave a retry signal. (Drive plumbing lives in
   `Sources/INMeetingsCore/Drive/`; reuse `DriveClient`.)

Signature (sketch):
```swift
public struct CompanyEditor {
    public init(store: MeetingStore, drive: DriveSync?)   // drive optional (nil when not connected)
    public func setCompany(meeting: MeetingRecord, name: String?) async throws
}
```
`name == nil` or whitespace-only → an **explicit clear**: `company.name = null`, `source = "user"`
(dashboard shows "Unknown" / Needs-linking; not re-guessed).

### 5. UI — `Apps/INMeetings/INMeetings/Dashboard/MeetingDetailView.swift`
The company in the detail header becomes **inline-editable**:
- Display the company; tapping it (or a trailing pencil) swaps to a `TextField` seeded with the current
  value, placeholder **"Add company"** when empty.
- **Commit** on Enter / focus-loss → call `CompanyEditor.setCompany`; **cancel** on Esc.
- Empty/whitespace commit → explicit clear.
- The **same control** serves rename (existing company) and assign (empty / Needs-linking) — no separate
  flow. Disabled while the meeting is still "processing" (status != done / syncing).
- Liquid Glass, English chrome, consistent with the existing header. After save, the row + header
  reflect the new name (the dashboard already observes the store).

---

## Data flow

**Edit:** user commits a name in the detail header → `CompanyEditor.setCompany(meeting, name)` →
(1) read-modify-write `metadata.json`, (2) `MeetingStore.updateCompany`, (3) if synced, re-upload
`metadata.json` to Drive. Dashboard refreshes from the store.

**Inference (unchanged trigger):** pipeline `done` → `metadata.json` written by Python with
`company.source` set → `MeetingStore.indexPackage` reads it. After a user edit, `metadata.json` holds
the user value, so a **re-index preserves it** (no clobber).

## Edge cases
- **Re-index after edit** → `metadata.json` already has the user value → preserved. ✅
- **Not-yet-synced meeting** → no Drive re-upload now; the corrected file uploads on first sync.
- **Title false positives** → conservative patterns + stoplists; user corrects via the same field.
- **Drive re-upload fails** → local + disk edit holds; logged, non-blocking, retried on next sync.
- **Concurrent edit while processing** → edit disabled until the meeting is done (avoids a two-writer
  race on `metadata.json`).

## Testing
- **Python** (`pipeline/tests/`): `resolve_company` title-fallback — `"Yuval <> Prelligence"` →
  `Prelligence`; `"IN Venture / Acme AI"` → `Acme AI`; `"Intro with Acme"` → `Acme`; **no match** on
  `"Weekly sync"`, `"1:1"`, `"Standup"`, `"IN Venture"`; domain still wins when present.
- **Swift** (`Tests/INMeetingsCoreTests/`): `MeetingStore.updateCompany` round-trips; `CompanyEditor`
  metadata edit sets `company.name`/`source` and **preserves other keys** (assert an untouched key
  survives); clear sets name null.
- **Manual:** rename a meeting in the dashboard → header + row update immediately; relaunch → persists;
  inspect `metadata.json` on disk → updated; for a synced meeting → the Drive copy updates; assign a
  company to a "Needs linking" meeting → leaves the bucket.

## Files touched
- `pipeline/in_meetings_pipeline/context_assembler.py` — title fallback + `source`.
- `schema/metadata.schema.json` + `schema/fixtures/golden-package/metadata.json` — `company.source`.
- `Sources/INMeetingsCore/Store/MeetingStore.swift` — `updateCompany`.
- `Sources/INMeetingsCore/Store/ContextPackage.swift` — `Company.source` (optional).
- **new** `Sources/INMeetingsCore/Store/CompanyEditor.swift`.
- `Apps/INMeetings/INMeetings/Dashboard/MeetingDetailView.swift` — inline edit.
- Tests: Python `resolve_company`, Swift `MeetingStore`/`CompanyEditor`.

## Out of scope (YAGNI)
- Transcript-content inference (NER).
- Moving/renaming the Drive **folder** on rename (only the file content updates).
- Editing the meeting **title** (this feature is company-only).
- CRM matching / `matched:true` / `sevanta_deal_id` (Phase 6).
- Bulk re-assign, autocomplete from prior companies (possible later polish).
