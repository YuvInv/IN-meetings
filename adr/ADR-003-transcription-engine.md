# ADR-003 — Transcription engine, biasing, diarization

**Status:** Proposed (updated by P1 prototype) · **Date:** 2026-06-11 · **Deciders:** Yuval (review)
**Brief item:** D · **Research:** RESEARCH.md §3 (the crux) · **Empirical:** `pipeline/benchmarks/P1-FINDINGS.md`

> **P1 UPDATE (validated on real founder-meeting audio, M4/macOS 26):** On-device speed and Hebrew
> quality are confirmed (RTF ≈ 0.10; strong baseline proper-noun rendering). **But `initial_prompt`
> biasing does NOT work** — Latin-script terms *regress* names (Algolion → "alcohol-ion"), Hebrew-script
> terms are neutral, and neither fixes the hardest term ("IN Venture"). **The context-injection mechanism
> is therefore deterministic post-correction, not prompt biasing** (validated — see "Biasing" below as
> amended and ADR-004). Engine/runtime/diarization decisions below are unchanged.

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

**Context biasing — AMENDED by P1.** The original plan (build `initial_prompt` from the ADR-004
vocabulary, terms last) was tested in P1 and **does not work**: the forced-Hebrew fine-tune won't emit
Latin, Latin-script prompt terms *regress* otherwise-correct names, and Hebrew-script terms don't help
the hard cases. **Decision: deterministic post-correction is the primary mechanism.** Take the ADR-004
vocabulary (each entity = canonical spelling + variant spellings, Hebrew + Latin) and whole-token
replace against the ASR output (`pipeline/benchmarks/postcorrect.py` PoC: "נדוויינצ'ר" → "IN Venture",
"פרליג'נס" → "Prelligence", etc. — deterministic, no regressions, and yields the canonical Latin
spellings the Claude skills want). `initial_prompt` is demoted to an optional light domain primer and
**must not contain Latin proper nouns**. Next: add a fuzzy/edit-distance pass for unseen variants
(guard short tokens). The CI check becomes a post-correction fixture test, not a prompt-following test.

**Diarization — two cases (see ADR-011):**

> **4c UPDATE (senko validated on real Hebrew, M-series/macOS 26):** A senko-vs-pyannote bake-off on
> `prelligence` (real founder meeting) settled the unvalidated-DER risk below: **senko matched Timeless
> ground-truth speaker counts at both scales** (2 on a 6-min clip, 3 on the full 51-min) at RTF
> ~0.001–0.004 — the English+Mandarin embedding model did not break Hebrew. **senko stays primary;
> pyannote `community-1` is the fallback** but is HuggingFace-gated (per-user token + model-terms), so
> it is *not* baked into onboarding. Implemented in `pipeline/in_meetings_pipeline/diarize.py`
> (`diarize_track` + `assign_speakers` max-overlap attribution); profile-aware in `__main__`. senko needs
> **Python <3.14** → the pipeline runs in a pinned 3.11 venv (DECISIONS 2026-06-11 slice 4c).
- **Call (dual-track):** run **senko** (MIT, ~7.7 s/hour on M3 via ANE) **on the system-audio track
  only** — the mic track is the known IN partner (the 2-track trick). Map system-track speakers to
  names via the calendar attendee list (ADR-004); unmatched stay `Speaker A/B`.
- **In-person (mic-only):** every participant is on the single mic track → run full **multi-speaker
  diarization on the mic track** (senko; pyannote community-1 fallback), map to calendar attendees, and
  let the user fix/rename in the dashboard (ADR-007). This is **per-speaker from v1** (Yuval) and a
  harder quality axis — **its own de-risk prototype** (IMPLEMENTATION_PLAN), with Hebrew DER + overlap
  + room-acoustics to validate. Validate Hebrew DER before trusting either path.

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
