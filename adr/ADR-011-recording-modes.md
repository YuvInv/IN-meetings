# ADR-011 — Recording modes: manual capture & in-person meetings

**Status:** Proposed · **Date:** 2026-06-11 · **Deciders:** Yuval (decided)
**Relates to:** ADR-001 (detection), ADR-002 (capture), ADR-003 (diarization), ADR-005 (package)

## Context

Auto-detection (ADR-001) covers app-based calls, but two cases need first-class support:

1. **Manual start** — a user must be able to start recording on demand: as a fallback when
   auto-detection misses a call, and as a deliberate action.
2. **In-person (face-to-face) meetings** — no app, no remote audio, nothing to auto-detect. The whole
   room is captured through the **microphone only**. This breaks the call-time "mic = me / system =
   them" two-track shortcut: every participant lands on one mic track, so telling them apart requires
   acoustic diarization on a single stream.

Decisions taken (Yuval): in-person is **manual-trigger only** (no calendar auto-prompt); in-person
needs **per-speaker labeling from v1**; manual Record **auto-picks the capture profile** from the P3
audio-process detector.

## Decision

### Entry points (how a recording starts)
1. **Auto (call detected)** — "Record now?" prompt (ADR-001), via Core Audio bidirectional process I/O.
2. **Manual** — a **menu-bar "Start Recording"** item **and a global hotkey**, available anytime
   regardless of detection. This is the fallback for missed calls and the primary path for in-person.
   In-person recordings are started **only** this way (no calendar auto-prompt).

### Capture profiles
- **Call profile (dual-track)** — mic (AVAudioEngine) + system/remote (Core Audio tap), two tracks
  (ADR-002). Used when a live call is present.
- **In-person profile (mic-only)** — AVAudioEngine mic → `audio_mic.wav`; **no system tap** (there is
  no remote audio). `audio_system.wav` is absent for in-person packages.

### Manual start auto-picks the profile (reusing P3 detection)
On manual Record, query the verified P3 signal (a process with bidirectional audio = a live call):
- **live call present → Call profile** (mic + system).
- **no call → In-person profile** (room mic only).
The chosen profile is shown on the banner; the user can flip it (e.g., force mic-only). Zero extra
clicks in the common case.

### In-person speaker attribution (per-speaker from v1)
The room-mic single-track case needs real diarization (the 2-track shortcut doesn't apply):
- Run **diarization on the mic track** (senko primary — fast on Apple Silicon; pyannote community-1
  fallback) to split into distinct speakers.
- **Map speakers to names** using the calendar event's attendee list when the meeting matches one
  (ADR-004); unmatched speakers stay `Speaker 1/2/…`.
- **Dashboard manual assignment** (ADR-007): the user can rename/merge speakers after the fact — the
  reliable backstop, since one-mic diarization won't be perfect.
- This is a distinct quality axis (like code-switching was for calls) and gets its own de-risk
  prototype before the in-person path is trusted (IMPLEMENTATION_PLAN).

### Context for in-person
Calendar does **not** auto-trigger in-person recording, but once started, the context assembler
(ADR-004) still matches the recording to a calendar event for **attendee names + company** — which is
exactly what the speaker-naming step needs. Degrades gracefully when no event matches.

## Consequences
- **Good:** one manual control covers both the "auto-detect failed" fallback and the entire in-person
  use case; profile auto-pick reuses detection we already verified; in-person gets real speaker labels.
- **Costs/risks:** **in-person multi-speaker diarization on a single mic is hard** — accuracy depends
  on room acoustics, overlapping speech, and (unvalidated) Hebrew DER; mitigated by calendar-name
  mapping + dashboard manual fixes, and de-risked by a dedicated prototype. A global hotkey needs an
  accessibility/Input-Monitoring-free mechanism (use `NSEvent` global monitor / `MASShortcut`-style).
  Package/metadata gains a `meeting_type` (ADR-005); downstream skills must handle a package with no
  `audio_system.wav` and all speakers on the mic track.

## Options considered
| Option | Why not |
|--------|---------|
| Calendar auto-prompt for in-person too | Yuval chose manual-only for in-person (fewer false prompts; in-person intent is deliberate). Calendar still used for naming, just not triggering. |
| In-person merged transcript (no diarization) for v1 | Yuval wants per-speaker from v1 — "who said what" is core value for room meetings. |
| Manual start always asks call-vs-in-person | Extra click every time; auto-pick from the audio signal is reliable and frictionless. |
| Mic-only for everything (skip the tap) | Loses remote-audio quality + the clean me/them split on calls; the tap is the better call-time path. |
