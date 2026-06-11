# Topic C2 — Hebrew ASR: Cloud APIs + Apple On-Device (as of 2026-06-10)

## 1. Ground truth: the ivrit.ai Hebrew Transcription Leaderboard

The [ivrit.ai leaderboard](https://huggingface.co/spaces/ivrit-ai/hebrew-transcription-leaderboard) (updated ~June 2026; raw data in [benchmark.csv](https://huggingface.co/spaces/ivrit-ai/hebrew-transcription-leaderboard/raw/main/benchmark.csv)) is the only neutral, multi-dataset Hebrew benchmark covering both local models and cloud APIs. WER on five sets (eval-d1 / eval-whatsapp / SASpeech / FLEURS-he / hebrew_speech_kan):

| Engine | eval-d1 | whatsapp | SASpeech | FLEURS | kan |
|---|---|---|---|---|---|
| **ivrit-ai/whisper-large-v3-ct2-20250513 (local)** | **.051** | **.072** | .064 | **.174** | **.081** |
| ivrit-ai/whisper-large-v3-turbo-ct2-20250513 (local) | .053 | .071 | .066 | .181 | .082 |
| **Soniox STT (cloud)** | **.048** | .090 | .065 | .177 | .114 |
| Amazon Transcribe (batch) | .066 | .104 | .085 | .230 | .090 |
| Deepgram Nova-3 | .067 | .120 | .102 | .233 | .210 |
| OpenAI gpt-4o-transcribe | .073 | .126 | .109 | .210 | **.394** |
| stock whisper large-v3 | .098 | .132 | .094 | .262 | .134 |
| ElevenLabs scribe_v1 | **.200** | **.264** | .068 | .181 | .109 |
| Google STT ("google-speech") | .211 | .352 | .189 | .385 | .292 |

**Headline: the local ivrit.ai CT2 models beat or match every cloud API on conversational Hebrew.** The eval-d1/eval-whatsapp sets are real Israeli conversational speech — the closest proxy to VC meetings. Latency data ([timing.csv](https://huggingface.co/spaces/ivrit-ai/hebrew-transcription-leaderboard/raw/main/timing.csv)) shows turbo-ct2 runs 24–61x realtime on NVIDIA GPUs (no Apple Silicon entry — must benchmark M3 yourself).

## 2. Per-vendor assessment

**ElevenLabs Scribe.** Marketing claims [3.1% FLEURS / 5.5% CommonVoice Hebrew](https://elevenlabs.io/speech-to-text/hebrew); the independent leaderboard measured scribe_v1 at **20–26% WER on conversational Hebrew** (fine on clean read speech: 6.8% SASpeech). ElevenLabs' [own docs](https://elevenlabs.io/docs/overview/capabilities/speech-to-text) place Hebrew in the *third* accuracy tier for Scribe v2 (">10% to ≤20% WER"). Capabilities: word-level timestamps, diarization up to 32 speakers (v2), keyterm prompting (batch: up to 1,000 terms; realtime: 50; third-party reporting says +20% cost). [Scribe v2](https://elevenlabs.io/blog/introducing-scribe-v2) is ~40% cheaper (~$0.22–0.40/audio-hr) and has [zero-retention modes](https://latenode.com/blog/tools-software-reviews/best-ai-tools-2025/elevenlabs-scribe-review-and-accuracy-test) for enterprise/HIPAA. Verdict: treat skeptically until Scribe v2 is benchmarked on your own conversational Hebrew audio.

**OpenAI.** [gpt-4o-transcribe](https://developers.openai.com/api/docs/models/gpt-4o-transcribe) supports the `prompt` parameter (usable for name biasing, but soft/unreliable), $0.006/min (~$0.36/hr); mini at $0.003/min. Decent on conversational Hebrew (7.3%/12.6%) but a **39.4% WER blowup on hebrew_speech_kan** signals hallucination/instability risk. Privacy is a plus: [/v1/audio/transcriptions is reportedly zero-data-retention by default](https://factually.co/fact-checks/technology/openai-zero-data-retention-zdr-how-it-works-and-eligible-endpoints-24179d), and API data isn't used for training ([data controls](https://platform.openai.com/docs/guides/your-data)).

**Google.** "google-speech" is the worst performer on the leaderboard (21–39% WER). [Chirp 2](https://docs.cloud.google.com/speech-to-text/docs/models/chirp-2) added word timestamps + model adaptation/phrase boosting, but per-language boost availability must be checked and no independent Hebrew benchmark shows it competitive. Gemini audio transcription has [documented hallucination issues](https://towardsdatascience.com/building-a-scalable-and-accurate-audio-interview-transcription-pipeline-with-google-gemini/) and no Hebrew benchmark. Skip.

**AssemblyAI.** Hebrew supported only on **Universal-2**, in their own "Good accuracy (>10% to ≤25% WER)" tier ([supported languages](https://www.assemblyai.com/docs/supported-languages)). [Keyterms prompting](https://www.assemblyai.com/docs/speech-to-text/universal-streaming/keyterms-prompting) (up to 1,000 terms) exists but on Universal-3-Pro/English+multilingual streaming — Hebrew falls back to Universal-2 without it. Not competitive.

**Deepgram Nova-3.** **Hebrew added February 2026** as a production monolingual RTL model with **streaming, batch, and Keyterm Prompting** plus numerals formatting ([announcement](https://deepgram.com/learn/speech-to-text-for-hebrew-persian-urdu-on-nova-3), [IT Nerd coverage, 2026-02-12](https://itnerd.blog/2026/02/12/deepgram-expands-language-coverage-with-hebrew-persian-and-urdu/)). Leaderboard: 6.7%/12.0% conversational — best-in-class among US cloud vendors. [~$0.46/hr PAYG](https://deepgram.com/pricing); diarization extra. Caveats: monolingual Hebrew model (code-switched English segments untested); training-data opt-out posture needs contract-level verification.

**Speechmatics.** Hebrew in its ~55 languages with [custom dictionary](https://docs.speechmatics.com/speech-to-text/features/custom-dictionary) (`additional_vocab`, up to 1,000 words/phrases with `sounds_like`) — confirmed available for Hebrew. Diarization included; batch from [$0.30–1.04/hr](https://www.speechmatics.com/pricing). UK/EU processing available. **Not on the ivrit.ai leaderboard** — unproven Hebrew accuracy; would need self-benchmark.

**Azure Speech.** [he-IL supported](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support) including fast transcription and **Custom Speech (audio + human-labeled transcript training)** — the heaviest-weight customization path of any vendor. Phrase-list availability for he-IL is *not confirmed* in the docs table ("locales where the feature is enabled"). Diarization available. No independent Hebrew benchmark; Microsoft doesn't train on customer audio and offers EU residency.

**Soniox (not in brief — the sleeper).** **Tops the cloud field on the ivrit.ai leaderboard** (4.8% eval-d1 — better than the best local model on that set). Supports [domain context biasing for Hebrew](https://soniox.com/speech-to-text/hebrew) (free-form hints: participant names, terminology — exactly the context-injection design), diarization + translation included, [~$0.10/hr async, $0.12/hr streaming](https://soniox.com/pricing) — cheapest option researched. Privacy: [no storage by default, never trains on customer data](https://soniox.com/docs/security-and-privacy), [EU data residency option](https://soniox.com/docs/stt/data-residency). Risk: small vendor.

## 3. Apple SpeechAnalyzer / SpeechTranscriber (macOS 26)

- **Hebrew (he_IL) IS now in `SpeechTranscriber.supportedLocales`** per two independent 2026 sources ([Gubarenko's iOS 26 SpeechAnalyzer guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide), [Crosley's framework comparison](https://blakecrosley.com/blog/speech-framework-vs-sfspeechrecognizer)) — the list expanded well beyond the ~10-language WWDC25 launch set (now ~42 locales incl. ar_SA, ru_RU, he_IL). Verify on a real macOS 26 box at project start ([Apple docs](https://developer.apple.com/documentation/speech/speechtranscriber) don't enumerate locales).
- Capabilities: fully on-device, long-form audio with no duration cap, automatic language management, time-aligned results ([WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)).
- **Critical gap: no custom vocabulary/contextual-strings API** (unlike legacy SFSpeechRecognizer) per [Forasoft's 2026 playbook](https://www.forasoft.com/blog/article/speech-recognition-with-neural-networks-on-ios-1621) — the context-injection bet cannot run through Apple's ASR. Hebrew quality is unbenchmarked anywhere (absent from ivrit.ai leaderboard).

## 4. Code-switching verdict

The [ivrit-ai/whisper-large-v3 model card](https://huggingface.co/ivrit-ai/whisper-large-v3) states language detection was deliberately degraded in training; the model is "intended for mostly-Hebrew audio" with the language token forced to Hebrew — i.e., English-dense passages are its weak spot. However, **no public Hebrew-English code-switching benchmark exists**; eval-d1/eval-whatsapp contain naturally code-switched Israeli speech and the ivrit models still win there. No cloud option demonstrably beats local ivrit.ai on code-switching by a margin that matters — Soniox is the only one at parity overall, and ElevenLabs' multilingual claims fail on conversational Hebrew (v1).

**Conclusion:** keep local ivrit.ai whisper-large-v3-turbo-ct2 as default. Best cloud fallback for hard audio: **Soniox** (accuracy + context biasing + zero-retention + price), with **Deepgram Nova-3 Hebrew** as the better-known-vendor alternative (keyterm prompting, weaker privacy default). Build an internal ~2-hr code-switched VC-meeting eval set in week one — it's the only way to settle the code-switching question and to test Scribe v2 and Apple's he_IL model, neither of which has independent numbers.