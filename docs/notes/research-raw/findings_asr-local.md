# C1 — Hebrew ASR, local/on-device candidates (verified June 10, 2026)

## 1. ivrit.ai model lineup (huggingface.co/ivrit-ai, 21 models)

Current Hebrew line (all fine-tunes of OpenAI whisper-large-v3 / -turbo) — [org model list](https://huggingface.co/ivrit-ai/models):

- **ivrit-ai/whisper-large-v3** (HF/transformers, upd. May 22 2025) — trained on **~5,050 h**: ~4,700 h Knesset plenums + ~300 h crowd-transcribe-v5 + ~50 h crowd recital; two-phase (Knesset pre-train 3 epochs, mixed post-train). Card explicitly warns: *language detection degraded; intended for mostly-Hebrew audio; translation task degraded* ([model card](https://huggingface.co/ivrit-ai/whisper-large-v3)).
- **ivrit-ai/whisper-large-v3-turbo** + **-ggml** builds (whisper.cpp/Vibe-ready, Apache-2.0, upd. May 22 2025) ([ggml card](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml)).
- **ivrit-ai/whisper-large-v3-ct2** and **-turbo-ct2** (faster-whisper/CTranslate2, upd. Oct 27 2025; turbo-ct2 = 13.5k downloads/mo). Turbo card lists 295 h crowd + 93 h professional ([card](https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ct2)).
- **whisper-large-v3-turbo-onnx** (Dec 20 2025) — newest artifact; signals a sherpa-onnx/streaming direction.
- **Licensing: Apache-2.0 on all current v3 models** (verified on the large-v3 and turbo-ct2/ggml cards). The custom-license concern applies only to legacy v2 (whisper-v2-d4 era). Commercial use is clear.
- `yi-whisper-*` models are **Yiddish**, not Hebrew — ignore.
- Bonus: ivrit-ai rehosts **ungated mirrors of pyannote-speaker-diarization-3.1 and segmentation-3.0** (MIT) — bundleable without HF token ([mirror](https://huggingface.co/ivrit-ai/pyannote-speaker-diarization-3.1)).

## 2. Live leaderboard standings (space updated ~June 6, 2026)

Pulled raw from the space's [benchmark.csv](https://huggingface.co/spaces/ivrit-ai/hebrew-transcription-leaderboard/raw/main/benchmark.csv). WER across 5 eval sets (eval-d1 / eval-whatsapp / saspeech / fleurs-he / hebrew_speech_kan):

| Model | d1 | whatsapp | saspeech | fleurs | kan |
|---|---|---|---|---|---|
| Soniox stt (cloud) | **.048** | .090 | .065 | .177 | .114 |
| **ivrit whisper-large-v3-ct2-20250513** | .051 | .072 | **.064** | **.174** | **.081** |
| **ivrit whisper-large-v3-turbo-ct2-20250513** | .053 | **.071** | .066 | .181 | .082 |
| amazon-transcribe batch | .066 | .104 | .085 | .230 | .090 |
| deepgram nova-3 | .067 | .120 | .102 | .233 | .210 |
| gpt-4o-transcribe | .073 | .126 | .109 | .210 | .394 |
| stock large-v3 (faster-whisper) | .098 | .132 | .094 | .262 | .134 |
| google-speech | .211 | .352 | .189 | .385 | .292 |

Takeaways: (a) the **local ivrit.ai 20250513 fine-tunes are at parity with the best commercial cloud (Soniox) and beat every other cloud API** — gpt-4o/Google are not competitive on Hebrew; (b) fine-tuning roughly **halves WER vs stock Whisper**; (c) the **turbo fine-tune gives up almost nothing vs full large-v3** (~0.002–0.007 WER) at ~half the compute; (d) eval-whatsapp 0.071 shows conversational (non-Knesset) speech holds up.

## 3. Apple Silicon runtimes (M3/16GB)

- **Critical gotcha: CTranslate2/faster-whisper has no Metal backend — CPU-only on macOS.** The exact artifacts the leaderboard evaluates (ct2) are the *wrong runtime* for Mac. Use the GGML (whisper.cpp) or a self-converted MLX build of the same weights ([Modal's whisper-variants overview](https://modal.com/blog/choosing-whisper-variants)).
- **mlx-whisper is ~2.0× faster than whisper.cpp** for large-v3-turbo (hyperfine, Jan 9 2026, [billmill benchmark](https://notes.billmill.org/dev_blog/2026/01/updated_my_mlx_whisper_vs._whisper.cpp_benchmark.html)); corroborated by [mac-whisper-speedtest](https://github.com/anvanvan/mac-whisper-speedtest). No prebuilt ivrit MLX model exists in [mlx-community](https://huggingface.co/mlx-community) — but [mlx-whisper](https://pypi.org/project/mlx-whisper/) `convert.py` converts any HF-format Whisper fine-tune (ivrit-ai/whisper-large-v3-turbo qualifies), with 4/8-bit quantization.
- **whisper.cpp**: full Metal GPU inference; optional Core ML ANE encoder ">3× faster than CPU-only"; memory table: large-class ~3.9 GB RAM / 2.9 GiB disk fp16, turbo roughly half, q5_0 quant cuts further ([whisper.cpp README](https://github.com/ggml-org/whisper.cpp)). Comfortable on 16 GB.
- **1-hour meeting estimate on M3** (community benchmarks, [JustVoice](https://justvoice.ai/blog/whisper-benchmark-apple-silicon-m3-m4), [PromptQuorum](https://www.promptquorum.com/local-llms/apple-silicon-whisper-metal-benchmark)): large-v3 ≈2–3× realtime via whisper.cpp Metal (~20–30 min); turbo ≈4–6× (~10–15 min); MLX turbo ≈2× that (~5–8 min). WhisperKit/ANE adds another 1.3–1.8× but custom-model conversion is heavier.

## 4. Code-switching + initial_prompt biasing

- Hebrew-centric fine-tunes are *deliberately* mostly-Hebrew (the ivrit card itself degrades language detection). The documented failure mode is mangling/transliterating cross-language terms — e.g. "makolet → Macaulay", "teudat zehut → Theodette Sahoot" ([Whisper Hebrish post, Nov 18 2025](https://huggingface.co/blog/danielrosehill/whisper-hebrish)). The only public "Hebrish" model is a **500-synthetic-sentence, single-speaker PoC** — not production-grade. No ivrit.ai code-switch model exists yet.
- **Prompt-following in fine-tunes is fragile**: ivrit.ai's first turbo training run *catastrophically forgot timestamp tokens and previous-text conditioning*; they retrained with ~100 h of timestamped/context-conditioned data specifically to restore it ([ivrit.ai training blog, Feb 13 2025](https://www.ivrit.ai/en/2025/02/13/training-whisper/)). So the context-injection bet must be empirically validated per model revision.
- **initial_prompt evidence**: only the **last ≤224 tokens** are consumed (put high-value terms at the end). Plain prompting biases spelling/proper nouns but is soft; stronger gains need architecture-level biasing (TCPGen: "considerable reduction in errors on biasing words" with 1,000-word lists — [Interspeech 2023](https://www.isca-archive.org/interspeech_2023/sun23e_interspeech.pdf); training-free variant [arXiv 2410.18363](https://arxiv.org/pdf/2410.18363)). LLM-generated context injected into Whisper prompts measurably improves proper-noun recognition ([Whisper: Courtside Edition, Feb 2026](https://arxiv.org/html/2602.18966)) — directly validates the calendar/CRM-vocabulary strategy, with the caveat that biasing English company names inside Hebrew prompts (mixed-script prompt) is untested territory.

## 5. Local diarization

- **senko** (MIT, 3D-Speaker pipeline): **1 h of audio in 7.7 s on M3** via CoreML/ANE; DER 13.5% VoxConverse; language-agnostic acoustics but embeddings trained on English+Mandarin — Hebrew unvalidated; now maintained inside the verbatim repo ([senko](https://github.com/narcotic-sh/senko)).
- **pyannote**: 3.1 is MIT (ungated ivrit mirror above); newer **community-1** (pyannote.audio 4.0, Sept 2025) is **CC-BY-4.0, gated registration**, with an ungated [pyannote-community mirror](https://huggingface.co/pyannote-community/speaker-diarization-community-1) ([announcement](https://www.pyannote.ai/blog/community-1)).
- **NVIDIA streaming Sortformer v2**: halves DER vs pyannote per its paper but **caps at 4 speakers** and drags in the heavy NeMo stack ([model](https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2), [paper](https://arxiv.org/pdf/2507.18446)).
- **whisperX** bundles faster-whisper + pyannote + wav2vec2 forced alignment and *does* ship a Hebrew aligner (`imvladikon/wav2vec2-xls-r-300m-hebrew` in DEFAULT_ALIGN_MODELS_HF, [source](https://raw.githubusercontent.com/m-bain/whisperX/main/whisperx/alignment.py)) — but inherits CT2's CPU-only Mac problem.
- **2-track advantage**: mic track = the known IN partner (no diarization needed); run diarization only on the system-audio track — fewer speakers, no cross-talk, much easier problem.

## Recommendation

**Primary**: `ivrit-ai/whisper-large-v3-turbo` (latest revision ≥20250513) **self-converted to MLX 8-bit, run via mlx-whisper**, with calendar/CRM vocabulary in `initial_prompt` (terms last, ≤224 tokens). Fastest path on M3, ~5–8 min/hour, leaderboard-parity accuracy. **Fallback runtime**: official `whisper-large-v3-turbo-ggml` on whisper.cpp Metal (zero conversion risk, ~10–15 min/hour). **Runner-up model**: full `ivrit-ai/whisper-large-v3` (GGML/MLX) when max accuracy matters and latency doesn't. **Diarization**: senko on the system-audio track (validate DER on Hebrew first), pyannote community-1 as quality fallback. Re-verify WER after quantization/conversion — leaderboard numbers were measured on CT2 fp16 artifacts, not GGML/MLX quants.