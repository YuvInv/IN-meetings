# Calendar panel → upload audio & assign to a meeting → context-aware processing — design BRIEF (2026-06-22)

**Status:** captured requirements (Yuval, 2026-06-22). **NOT yet designed** — this is the brief the next
session brainstorms into a full spec before building. **Reshapes** the existing P1 must-have "upload an
audio file for transcription" (IMPLEMENTATION_PLAN item 11) into a "more whole" feature.

## Vision (Yuval's words, paraphrased)
Before supporting a bare audio-file upload, make the feature whole:
1. Add a **right-side panel to the dashboard** that presents the user's **calendar** (after they've connected
   their Google account).
2. The user **clicks a meeting** in that panel and chooses to **upload an audio file and assign it to that
   meeting**.
3. Because the file is bound to a calendar event, the system has **context** — the meeting's time,
   participants, company — and can use it to enrich processing and **infer the sides of the conversation
   (speaker isolation?)**.

So the calendar meeting is the **entry point and the context source** for an imported recording, instead of a
context-free file import.

## Why this shape
The live-capture path already gets rich context for free (calendar match + dual mic/system tracks). An
imported file (e.g. a phone recording) has neither. Binding the upload to a chosen calendar event recovers the
**context** (attendees, company, time) and gives the user an obvious, meeting-centric place to do it.

## Existing building blocks (reuse, don't rebuild)
- **`CalendarClient`** (Swift, Google Calendar API) + **`CalendarContext`** (transform → context package) —
  already fetch + shape calendar events for live-call context (Phase 2). The panel and the assignment reuse
  these.
- **Dashboard** = `NavigationSplitView` (sidebar + detail). A right panel is naturally a SwiftUI
  **`.inspector()`** (macOS 14+) or a third split column.
- **Audio import** = the planned **synthetic `job.json`** pointing at the imported file (item 11) → the normal
  pipeline (ASR → post-correct → diarize → package) → dashboard + Drive.
- **Diarization** (senko) separates speakers; **`SpeakerEditor`** does manual one-tap speaker→name assignment
  (persisted to `transcript.json`).
- **Context package schema** already reserves attendee/company fields (slice 5) — an imported+assigned meeting
  fills the same fields.
- **`DriveAuth`** (Google connection + status) gates the panel (show "Connect Google" when disconnected).

## Key open questions / decisions for next session
1. **Calendar panel scope** — which events (today / next 7 days / past 30 days / searchable)? Read-only list?
   Refresh cadence? Empty/disconnected states. (Lean: a compact agenda list, recent + upcoming, reusing
   `CalendarClient`.)
2. **Upload-and-assign flow** — pick event → file picker → build a synthetic `job.json` **plus** a context
   pre-filled from that event via `CalendarContext` (attendees, start/end, company-by-domain) → `JobBridge`
   runs the pipeline → the meeting appears in the dashboard as an **imported** meeting with context attached.
   (Decide: a new meeting `type` / source flag; where it lands; can you re-assign / fix the event later.)
3. **Speaker isolation — set realistic expectations (the crux).** Diarization separates speakers
   *acoustically*; the calendar attendee list gives **candidate identities** to *label* them. **Automatic
   identity→speaker mapping needs voice-ID** — a separate, hard project (today's speaker-naming is manual
   one-tap). So a realistic v1 = *N separated speakers + the attendee list as one-tap label candidates*
   (assisted, not fully automatic). Confirm this is the expectation, or scope a heuristic (e.g. 2-party
   "me vs them") — but an uploaded mixed file usually can't reliably name "them" without voice-ID.
4. **Single-track reality.** An uploaded file is usually **one mixed track** (no separate mic/system), so the
   "me vs them" separation that live dual-track capture gives for free is **not** available — diarization must
   do all the work. This materially changes the speaker model vs live calls; the pipeline's import path should
   treat it as single-track.
5. **Calendar-first vs audio-first** — can you also create a meeting from a calendar event with **no audio yet**
   (and add audio later), or attach audio to an already-recorded meeting? Clarify the entry points.
6. **Privacy** — confidential deals: the panel reads calendar titles/attendees; keep on-device handling
   consistent with the rest of the app.

## Rough approach sketch (to be validated in brainstorming, not final)
Right-panel calendar (inspector) reusing `CalendarClient` → an event row action "Upload recording…" → file
picker → construct a synthetic `job.json` + a `CalendarContext`-derived context for that event → `JobBridge`
runs the standard pipeline (single-track import) → the meeting shows in the dashboard with context +
diarized speakers + the attendee list as label candidates for `SpeakerEditor`.

## Out of scope (for the first cut, unless decided otherwise)
- True automatic voice-ID / speaker identification (separate project).
- Editing/creating calendar events (read-only panel).
- Bulk import.
