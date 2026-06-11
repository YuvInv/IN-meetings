# P1 benchmark — Hebrew + code-switching ASR

De-risk prototype for [ADR-003](../../adr/ADR-003-transcription-engine.md). Findings: [P1-FINDINGS.md](P1-FINDINGS.md).

Data (audio, transcripts, model weights) is **gitignored** — audio/transcripts are confidential meeting
content; the model is 1.5 GB. Regenerate locally:

## Setup
```bash
brew install whisper-cpp ffmpeg
mkdir -p models eval_audio results
curl -L -o models/ivrit-large-v3-turbo.ggml.bin \
  https://huggingface.co/ivrit-ai/whisper-large-v3-turbo-ggml/resolve/main/ggml-model.bin
```

## Get eval audio
Pull a real Hebrew meeting via the `timeless` skill (recording endpoint → signed media URL), then:
```bash
ffmpeg -y -i eval_audio/<meeting>.src -ar 16000 -ac 1 -c:a pcm_s16le eval_audio/<meeting>.wav
ffmpeg -y -i eval_audio/<meeting>.wav -t 360 -c copy eval_audio/<meeting>_6min.wav   # quick clip
```

## Run
```bash
./run_benchmark.sh eval_audio/<meeting>_6min.wav                 # no prompt
./run_benchmark.sh eval_audio/<meeting>_6min.wav "<bias prompt>" # with initial_prompt
python3 compare_terms.py results/*_noprompt.txt results/*_biased*.txt
python3 postcorrect.py results/<meeting>_6min_noprompt.txt results/<meeting>.vocab.json
```

`*.vocab.json`: `[{"canonical": "...", "variants": ["...", "..."]}, ...]` — the context assembler
(ADR-004) generates this per meeting.

## Headline result
On-device is fast (RTF ≈ 0.10 on M4) and Hebrew quality is strong. `initial_prompt` biasing does **not**
help (Latin terms regress proper nouns) → **deterministic post-correction is the mechanism** (`postcorrect.py`).
