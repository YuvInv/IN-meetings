# ADR-003 — Transcription engine, biasing, diarization

**Status:** Proposed · **Date:** 2026-06-11 · **Deciders:** Yuval (review)
**Brief item:** D · **Research:** RESEARCH.md §3 (the crux)

## Context

Hebrew with heavy Hebrew↔English code-switching is the make-or-break quality axis, on confidential
calls (on-device by default). The live ivrit.ai leaderboard (verified against `benchmark.csv`) shows
**local ivrit.ai Whisper fine-tunes at parity with the best cloud API (Soniox) and beating Amazon,
Deepgram, gpt-4o-transcribe, ElevenLabs, and Google** on conversational Hebrew — and they're
Apache-2.0. So on-device carries **no quality penalty**. Key constraints from research:

- **CTranslate2/faster-whisper has no Metal backend (CPU-only on macOS)** — the CT2 artifacts the
  leaderboard scores are the wrong *runtime* for Mac. Use **GGML (whisper.cpp Metal)** or **MLX**.
- The **turbo** fine-tune is within ~0.002–0.007 WER of full large-v3 at half the compute → default.
- **initial_prompt** consumes only the last ~224 tokens; biasing helps proper nouns *softly*; the
  ivrit.ai fine-tune's prompt-following is real but **fragile** (a past revision catastrophically
  forgot it) → pin revisions and regression-test.
- **No public Hebrew↔English code-switching benchmark exists** anywhere.
- Apple SpeechTranscriber supports `he_IL` on macOS 26 but **has no custom-vocabulary API** → cannot
  carry the context-injection bet.

## Decision

**Primary engine: `ivrit-ai/whisper-large-v3-turbo` (pinned revision ≥ 20250513), on-device.**

- **Runtime:** **whisper.cpp with Metal**, using ivrit.ai's official **GGML** build — zero conversion
  risk, ~10–15 min per 1-hour meeting on M3. Ship an optional **MLX 8-bit** path (self-converted ivrit
  weights, ~5–8 min/hr) once we've re-benchmarked its quantized WER. Optional Core ML ANE encoder for
  extra speed.
- **Runner-up model:** full `ivrit-ai/whisper-large-v3` (GGML) when max accuracy matters and latency
  doesn't (e.g., a re-transcribe action in the dashboard).
- **English-heavy meetings:** because the fine-tune forces Hebrew, route meetings detected as mostly
  English (from calendar/locale heuristics, or a quick language probe) to **stock whisper-large-v3** —
  don't let the Hebrew fine-tune mangle an all-English call.

**Context biasing (the strategic bet):** build the `initial_prompt` from the ADR-004 vocabulary —
founder names, company name, product/domain terms, investor names — **highest-value terms placed last**
(only ~224 tokens are honored). Treat mixed-script prompts (English names inside a Hebrew prompt) as
**unvalidated** → measure it in Prototype 1. Pin the model revision and add a **prompt-following
regression test** to CI so a future model bump can't silently break injection. If plain prompting
proves too soft, the fallback is term-level post-correction (fuzzy-match ASR output against the known
vocabulary) — cheap and deterministic.

**Diarization:** run **senko** (MIT, ~7.7 s/hour on M3 via ANE) **on the system-audio track only** —
the mic track is the known IN partner and needs no diarization (the 2-track trick). Map diarized
system-track speakers to names using the calendar attendee list (ADR-004); unmatched speakers stay
`Speaker A/B`. Validate Hebrew DER first; **pyannote community-1** (CC-BY-4.0, ungated ivrit mirror) is
the quality fallback.

**Outputs (both):**
- `transcript.json` — `{ language, engine, model_revision, biased: bool, utterances: [{text, start,
  end, speaker_id, confidence}], speakers: [{id, name?, email?, side: "internal"|"external"}] }`.
  Confidence is preserved so `generate-mom`/critical-analysis can flag low-confidence numbers
  (מיליון vs מיליארד).
- `transcript.txt` — clean, speaker-named, readable.

**Slide / screen-share context — opt-in, OCR not video.** When enabled, sample the shared-screen region
periodically (every N seconds or on slide change) and run **Apple Vision OCR** (on-device, supports
Latin + Hebrew) → `slides_ocr.md` with timestamps. This captures what pure audio loses (slide text,
dashboards) at a fraction of video's cost. A VLM caption pass is a later enhancement, not v1.

**Cloud fallback — opt-in, documented (ADR-010).** For hard audio the user explicitly flags,
re-transcribe via **Soniox** (tops cloud Hebrew, free-form context biasing, included diarization,
~$0.10–0.12/hr, **zero-retention + EU residency**). **Deepgram Nova-3 Hebrew** (keyterm prompting) is
the better-known-vendor alternative. Never automatic; per-meeting consent; the choice and the data sent
are logged in `metadata.json`.

## Options considered

| Option | Why not (as primary) |
|--------|----------------------|
| Cloud ASR primary (Soniox/Deepgram/Scribe) | No quality win over local on Hebrew; confidentiality cost. Scribe specifically collapses on conversational Hebrew (20–26% WER) despite marketing. Keep Soniox as opt-in fallback only. |
| faster-whisper/CT2 (leaderboard format) | CPU-only on macOS — too slow; wrong runtime. |
| Apple SpeechTranscriber | No custom-vocabulary API → can't do context injection (the whole edge). Possible later use: a live-captions view. |
| Full large-v3 as default | ~2× compute for ~0.005 WER — turbo is the right default; keep full as the runner-up. |
| Record video for slide context (default) | Storage-heavy/intrusive; OCR captures the text that matters. |

## Consequences

- **Good:** best-measured Hebrew accuracy, fully on-device, commercially licensed, fast enough on M3;
  the 2-track trick makes diarization easy and cheap; OCR adds slide context without video.
- **Costs/risks:** code-switching quality is unproven until we build the eval set (Prototype 1);
  prompt-injection effectiveness with mixed scripts is the central bet to validate; GGML/MLX quantized
  WER must be re-measured (leaderboard used CT2 fp16); senko's Hebrew DER is unvalidated. All three are
  explicit Prototype-1 deliverables.
- **Mandatory week-one work:** assemble a ~2-hour internal **code-switched VC-meeting eval set** (pull
  real past meetings via the `timeless` skill) and benchmark: turbo-GGML vs turbo-MLX vs full, with and
  without biasing, plus M3 real-time factor. This settles every open ASR question with data.
