# ADR-002 — Capture pipeline (dual-track, no driver)

> **⚠️ Amended 2026-06-14** (see [DECISIONS.md](../DECISIONS.md)): **call video is ON by default** (ScreenCaptureKit window-only, HEVC) — not "off by default" — and is a **P1** deliverable (adds the Screen-Recording grant + a retention/size cap). The dual-track audio capture design below stands.

**Status:** Proposed · **Date:** 2026-06-11 · **Deciders:** Yuval (review)
**Brief item:** B · **Research:** RESEARCH.md §1 (capture mechanism), §4

## Context

We need the remote participants' audio and the user's mic as **separate tracks** — the single
highest-leverage decision for speaker attribution (mic = the IN partner; system = "them"). No virtual
drivers allowed. Two capture routes exist on macOS 26: ScreenCaptureKit (SCK) and Core Audio process
taps. Research is decisive on the difference:

- **SCK** can capture system audio + mic, but **cannot do an audio-only stream** (the content filter
  must name screen content), is gated on **Screen Recording TCC**, and triggers the **Sequoia/Tahoe
  "Allow For One Month" re-approval nag** — the top silent-failure cause for SCK-based recorders.
- **Core Audio process taps** (`CATapDescription` + `AudioHardwareCreateProcessTap`, macOS 14.2+)
  capture system **or per-process** audio with **only "System Audio Recording Only" TCC** — no Screen
  Recording, no admin password, and (community-evidenced, to verify on Tahoe) **no monthly nag**.
  Production-proven by Audio Hijack; reference impl: insidegui/AudioCap.
- Voice-processing AEC on the mic **ducks other audio** — it can degrade the very system track we're
  recording. Confirmed against Apple's `voiceProcessingOtherAudioDuckingConfiguration` docs.

## Decision

**Two independent tracks, SCK-free for audio:**

1. **System / remote track — Core Audio process tap.** Create a tap pinned to the detected meeting
   process (Zoom / Teams / the browser / Slack) when we can identify it, falling back to a
   system-exclusive tap (everything except our own process via `excludesCurrentProcess`-equivalent).
   Per-process tapping is preferred — it **excludes notification dings, Slack pings, and music** from
   the recording, which is both a transcription-quality and a **confidentiality** win. Tap → aggregate
   device (`kAudioAggregateDeviceTapListKey`) → `AudioDeviceCreateIOProcIDWithBlock` → write
   `audio_system.wav` (48 kHz). 
2. **Mic track — AVAudioEngine.** `inputNode` → `audio_mic.wav`, **recorded raw (no voice processing)
   by default.** Because the tap track is a perfect far-end reference, **echo cancellation runs offline
   in the pipeline** (the tap = exactly the remote audio leaking into the mic). Only when the user is on
   built-in speakers and offline AEC is insufficient do we enable VPIO with `duckingLevel = .min`.

**Formats:** WAV/PCM 48 kHz on disk during capture (lossless, simplest for ASR + AEC). Optionally
transcode to a compressed format for archival after transcription; keep WAV until the package is built.

**Video — off by default, opt-in per meeting/setting.** Video (shared screens/slides) is valuable
context but storage-heavy and more intrusive. When enabled, capture via **SCK** (this is where Screen
Recording TCC and the nag apply — acceptable because it's opt-in and occasional) and encode **HEVC**.
The default-on alternative to video for slide context is **periodic screen-share OCR** (ADR-003),
which is far cheaper and captures the gold (slide text) without storing video. Recommendation:
**audio-only default; video an explicit toggle; OCR the middle path.**

**Two capture profiles (see ADR-011).** The above is the **call profile** (dual-track). For **in-person
meetings** there is no remote audio, so the **in-person profile is mic-only**: AVAudioEngine →
`audio_mic.wav`, no system tap, no `audio_system.wav`. Manual Record auto-selects the profile from the
P3 detector (live call → dual-track; else → mic-only). In-person speaker separation moves from the easy
2-track split to single-track diarization (ADR-003/ADR-011).

**Meeting-end detection → auto-stop → post-process.** Stop when the meeting app closes/backgrounds AND
mic-in-use falls, debounced ~20–30 s (so a brief pause or screen-share switch doesn't end the
recording). Manual Stop always available on the banner. On stop: finalize WAVs, write the raw folder,
enqueue the pipeline job (ADR-009). A hard cap (e.g., 4 h) guards runaway captures.

## Options considered

| Option | Why not |
|--------|---------|
| SCK for audio (Granola/Notion/ChatGPT route) | Screen Recording TCC + monthly nag = missed recordings; whole-system mix (can't isolate the meeting app). |
| Single mixed track | Throws away the free Me/Them separation that two tracks give — the core attribution advantage. |
| VPIO/AEC always on for the mic | Ducks/degrades the system track we're recording; gain reduction. Raw + offline AEC is cleaner. |
| Always record video | Storage-heavy, more intrusive; OCR captures most of the value for confidential calls. |
| Virtual audio driver (BlackHole/Loopback) | Forbidden by constraints; team-rollout non-starter. |

## Consequences

> **P2 VERIFIED (M4/macOS 26.5):** dual-track tap+mic capture works end-to-end with **only the System
> Audio Recording permission** (no Screen Recording). Tracks are cleanly separate (mic = Hebrew voice,
> system = the other party) — no cross-bleed. **Implementation gotcha for the MVP:** the tap delivers
> **interleaved** float32; create the output `AVAudioFile` with the tap's exact processing format
> (`commonFormat` + `interleaved:true`) or `write(from:)` fails with −50 and the file is silent.

- **Good:** clean two-track audio with no driver; minimal permissions (no Screen Recording for the
  default audio path); per-process isolation improves both quality and confidentiality; offline AEC
  avoids the VPIO ducking trap.
- **Costs/risks:** Core Audio taps are sparsely documented and there's **no public API to query/request
  the audio permission** (use private TCC SPI / provoke-on-first-use — fine for internal distribution,
  an App Store blocker → ADR-009 chooses internal signing). The "no monthly nag for taps" advantage is
  community-evidenced — **Prototype 2 must confirm on Tahoe**. macOS 26.x audio regressions reported →
  pin a capture regression test per point release. AirPods-as-mic + built-in-speaker aggregate edge
  cases need testing.
- **Prototype 2** is exactly this pipeline: dual-track tap+mic capture, offline AEC, and the Tahoe
  permission/nag behavior.
