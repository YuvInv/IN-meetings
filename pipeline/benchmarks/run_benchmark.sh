#!/usr/bin/env bash
# P1 ASR benchmark — Hebrew + code-switching, on-device (whisper.cpp Metal + ivrit GGML).
# Reproducible harness behind the findings in P1-FINDINGS.md.
#
# Usage:
#   ./run_benchmark.sh <audio.wav> [prompt_string]
# Requires: whisper-cli (brew install whisper-cpp), models/ivrit-large-v3-turbo.ggml.bin
set -euo pipefail
cd "$(dirname "$0")"

AUDIO="${1:?usage: run_benchmark.sh <audio.wav> [prompt]}"
PROMPT="${2:-}"
MODEL="models/ivrit-large-v3-turbo.ggml.bin"
BASE="results/$(basename "${AUDIO%.*}")_$([ -n "$PROMPT" ] && echo biased || echo noprompt)"
mkdir -p results

[ -f "$MODEL" ] || { echo "missing model: $MODEL"; exit 1; }
command -v whisper-cli >/dev/null || { echo "missing whisper-cli (brew install whisper-cpp)"; exit 1; }

ARGS=(-m "$MODEL" -f "$AUDIO" -l he -bs 5 -of "$BASE" -otxt -oj)
[ -n "$PROMPT" ] && ARGS+=(--prompt "$PROMPT")

echo "audio=$AUDIO  prompt=$([ -n "$PROMPT" ] && echo "\"$PROMPT\"" || echo none)"
/usr/bin/time -p whisper-cli "${ARGS[@]}" 2>"$BASE.log"
echo "--- timing ---"; grep -E "real|total time|encode time" "$BASE.log" || true
echo "--- output: $BASE.txt ---"; head -c 300 "$BASE.txt"; echo
