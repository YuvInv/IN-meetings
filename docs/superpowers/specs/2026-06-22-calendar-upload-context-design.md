# Calendar panel → upload audio & assign to a meeting → context-aware processing — DESIGN (2026-06-22)

**Status:** designed + approved (Yuval, 2026-06-22). Supersedes the BRIEF
(`2026-06-22-calendar-upload-context-brief.md`). Reshapes the P1 must-have "upload an audio file for
transcription" (IMPLEMENTATION_PLAN item 11) into a calendar-anchored import flow.

## Goal

Let a user import a recording that was made **outside** the app (a phone recording, an external call
recording) and give it the same rich context a live capture gets for free. The entry point and context
source is a **calendar event**: pick the meeting it belongs to → upload the audio → the event's attendees,
company, and time enrich the transcription package, and the attendee list becomes one-tap label candidates
for the diarized speakers.

## Confirmed decisions (this brainstorm)

1. **Speakers = assisted labeling.** Diarization separates the file into Speaker 1…N; the assigned event's
   attendees become **one-tap label candidates** in the existing speaker chips. No automatic voice-ID
   (a separate, hard project). This is the realistic v1 and reuses the existing `SpeakerEditor` UX.
2. **Entry: event-preferred, with a no-event fallback.** Primary flow is calendar-first (pick event →
   upload). A **"Upload without an event…"** path always works so an ad-hoc recording is never blocked
   (it imports with no attendee context; company + speaker names set by hand).
3. **Calendar panel = a day-at-a-time agenda.** Opens on **today**; **◀ / ▶** page older/newer days; a
   **"Today"** shortcut; a **⟳ refresh** re-syncs the shown day from Google Calendar (days are cached
   otherwise). Each event row: time · title · attendee count + an **"Upload recording…"** action. Events
   that already have a recording show **"✓ recorded"** (click → opens that meeting). Panel is gated on
   Google being connected.
4. **Representation.** Imports live in the same **All Meetings** list, fully editable (company, speaker
   names) like any meeting, distinguished by a small **"Imported"** badge (`source` field). Re-assigning an
   import to a *different* calendar event after the fact is **out of scope** for v1.
5. **Single mixed track.** An uploaded file is treated as one track (processed with the pipeline's
   `inPerson` profile, which already does single-track diarization). No "me vs them" track split is
   available for imports.

## User-facing behavior

### The calendar panel
- A toggleable **right-side inspector** on the dashboard, opened/closed by a toolbar button; open/closed
  state is remembered.
- **Disconnected state:** a "Connect Google" prompt (reuses `DriveAuth.connect()`), no agenda.
- **Connected state — day agenda:**
  - Header: `◀  Wed · Jun 22  ▶`  with a **Today** button and a **⟳** refresh button.
  - Body: the selected day's events, sorted by start time. Each row shows start–end time, title, and an
    attendee count. All-day events are listed under a small "All day" header (no upload action — not a
    recordable meeting unless it has a time; see edge cases).
  - Row action: **"Upload recording…"**. If the event already has a recording linked → show **"✓ recorded"**
    and clicking the row opens that meeting in the detail pane.
  - Footer: **"Upload recording without an event…"** (the no-event fallback).
- Paging is instant from a per-day cache; **⟳** forces a re-fetch of the shown day.

### Upload & assign flow
1. User clicks **Upload recording…** on an event (or the no-event footer).
2. Native file picker, accepting common audio/video containers (`.m4a .wav .mp3 .aac .mp4 .mov .caf …`).
3. The app creates a new meeting folder, **normalizes the file to a pipeline-compatible track**
   (16 kHz mono WAV via AVFoundation; audio is extracted if a video container is chosen), and — for the
   event path — writes a `context.input.json` **pinned to the chosen event**.
4. A synthetic `job.json` (`profile: "inPerson"`, single track, `source: "import"`) is written and the
   **existing pipeline** runs (ASR → post-correct → diarize → package), exactly as a live capture does.
5. The meeting appears in **All Meetings** with a "Processing" state, then resolves to the normal detail
   view: transcript, diarized speakers, and — when an event was assigned — the company, title, and
   attendee chips for one-tap speaker labeling.

### Speakers
- Pipeline output: `Speaker 1…N`, `side: "unknown"` (the `inPerson` path).
- The assigned event's attendees flow into the package (`metadata.attendees`) via the pinned
  `context.input.json`, so the existing speaker-chip menu offers them as quick-pick label candidates.
- No-event imports have no attendee candidates → user types names via the existing "Custom name…" path.

## Architecture & components

### Reuse (do not rebuild)
- **`CalendarClient.fetchEvents(timeMin:timeMax:)`** — the day agenda fetches `[startOfDay, endOfDay]`
  for the selected day.
- **`CalendarContext`** — extended with a method to write `context.input.json` **pinned to one known
  event** (instead of the live path's time-window candidate fetch). The chosen `CalendarEvent` already
  carries attendees + summary + start/end, so no second network call is needed.
- **The pipeline** — unchanged contract. `profile: "inPerson"` already diarizes a single track and the
  packaging step already reads `context.input.json` to fill `metadata.attendees` / `company` /
  `meeting.calendarEventId`.
- **`SpeakerEditor`** + the `MeetingDetailView` speaker chips — attendee quick-pick already exists.
- **`DriveAuth`** — gates the panel; reused for the "Connect Google" prompt.

### New (Swift app)
- **`CalendarPanel` view + view model** — day-agenda inspector. Owns: selected day, per-day event cache,
  loading/error state, day paging, refresh. Renders rows + upload actions. Gated on `DriveAuth.isConnected`.
- **Inspector toggle** — a toolbar button on `DashboardWindow` driving `.inspector(isPresented:)`; persisted
  open/closed (e.g. `@AppStorage`).
- **`ImportCoordinator`** — orchestrates: create meeting folder → normalize/extract audio to
  `audio.wav` (AVFoundation) → (event path) write pinned `context.input.json` → write synthetic `job.json`
  → hand to `JobBridge` to run the pipeline + index + Drive-sync (the existing post-run path).
- **`JobBridge` import entry** — a new `enqueueImport(...)` (or a generalized enqueue) that runs the same
  pipeline/index/sync path as live capture, but from a prepared folder + synthetic job rather than a
  `CaptureSession.Result`.

### Data model changes
- **`MeetingRecord`** gains two nullable columns (migration **v4**):
  - `source: String` — `"live"` (default/backfill) | `"imported"`. Surfaced as the badge.
  - `calendarEventId: String?` — populated at index time from `metadata.meeting.calendarEventId` for
    **both** live and imported meetings. Lets the panel mark events as **"✓ recorded"** and lets a row
    click open the linked meeting. (Live captures that matched an event get this for free going forward.)
- **`job.json`** gains an optional `source: "import"` flag (live omits it / `"live"`). Tracks carry a
  single entry (`{"mic": "audio.wav"}`); `profile: "inPerson"`.

### Data flow
```
[Calendar panel] --pick event--> [ImportCoordinator]
   file picker --> audio.wav (16k mono, AVFoundation)
   event       --> context.input.json (pinned to event)  [event path only]
               --> job.json (profile: inPerson, source: import)
        |
        v
[JobBridge.enqueueImport] --> python -m in_meetings_pipeline run job.json
        |                         ASR -> post-correct -> diarize(senko) -> package
        |                         (packaging reads context.input.json -> attendees/company/eventId)
        v
[indexPackage] -> MeetingRecord{source: imported, calendarEventId} -> SQLite
        |
        v
[Dashboard] All Meetings (Imported badge) -> detail: transcript + Speaker 1..N
            + attendee quick-pick chips (assisted labeling) + Drive sync
```

## Error handling & edge cases
- **Disconnected Google:** panel shows Connect prompt; the no-event upload path still works from the footer.
- **Calendar fetch fails / times out:** the shown day surfaces an inline error with a retry (⟳); paging to
  other days still works from cache; never blocks an upload already in flight.
- **Unsupported / corrupt file:** AVFoundation normalization fails → surface a clear error, no folder left
  behind (clean up the partial meeting folder).
- **Video container chosen:** extract the audio track only; v1 does **not** retain/play the video for
  imports (audio-only playback, like an audio-only live call).
- **Silent / near-silent import:** the existing `asr.is_silent` gate + Silero VAD apply unchanged.
- **Event with no attendees / internal-only domain:** import succeeds; company falls back to the existing
  inference (domain/title) → may be "Unknown company"; speakers labeled by hand.
- **All-day / no-time events:** not offered an upload action (no meaningful start/end to seed context).
- **Re-importing the same file to the same event:** allowed (creates a separate meeting); no dedupe in v1.
- **`metadata.meeting.type` for imports:** processing profile is `inPerson` (single track); `type` is
  derived from context (default `"call"` when the event has external attendees) — provenance is carried by
  the new `source` field, not by overloading `type`.

## Testing
- **Swift unit:**
  - synthetic `job.json` builder → correct fields (`profile: inPerson`, single track, `source: import`).
  - pinned `context.input.json` from a `CalendarEvent` → correct attendees/company/start/end/eventId.
  - `CalendarPanel` view model: day paging, per-day cache hit vs refresh re-fetch, disconnected/error states.
  - `MeetingRecord` migration v4: backfill `source="live"`, nullable `calendarEventId`; index populates
    `calendarEventId` from metadata.
- **Python:** confirm/extend a single-track `inPerson` import test → N speakers, `side="unknown"`; packaging
  fills attendees/company/eventId from a pinned `context.input.json`.
- **Manual (Yuval at the GUI):**
  1. Connect Google → open panel → today's agenda renders.
  2. Page ◀/▶ across days; **Today** returns; **⟳** re-syncs.
  3. Pick an event → upload an `.m4a` → meeting processes → company + title from the event; attendees appear
     as speaker-chip quick-picks → assign two speakers → names persist (+ re-upload to Drive).
  4. A live-captured meeting that matched an event shows **"✓ recorded"**; clicking opens it.
  5. **Upload without an event** → imports with no attendee context; set company + speaker names by hand.
  6. Upload a video container → audio is extracted and transcribed (no video player).

## Out of scope (v1)
- Automatic voice-ID / identity→speaker mapping (separate project).
- Editing/creating calendar events (read-only panel).
- Re-assigning an import to a different event after the fact.
- Retaining/playing imported **video**.
- Bulk import; dedupe of re-imports.
