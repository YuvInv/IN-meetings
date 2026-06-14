#!/usr/bin/env bash
#
# QA for slice 5 (context package + SQLite index) — "for dummies" edition.
#
# HOW TO USE:
#   1. Open the app, record a short meeting (a real call, or in-person), then press Stop.
#   2. Wait ~10-30s for the "Transcribing…/Packaging…" status to reach done.
#   3. Run:   ./scripts/qa-slice5.sh
#      (or check a specific meeting:  ./scripts/qa-slice5.sh 2026-06-14_15-30-00)
#   4. Read the ✅ / ❌. Green all the way down = slice 5 works end to end.
#
set -uo pipefail

APP_SUPPORT="$HOME/Library/Application Support/IN Meetings"
REC_DIR="$APP_SUPPORT/Recordings"
DB="$APP_SUPPORT/meetings.db"

# Repo root = the parent of this script's dir (falls back to the dev path).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
[ -d "$REPO/schema" ] || REPO="/Users/yuvalnaor/repos/IN-meetings"
PY="$REPO/pipeline/.venv/bin/python"
SCHEMA="$REPO/schema"

FAILED=0
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; GB=$'\033[1;32m'; RB=$'\033[1;31m'; X=$'\033[0m'
else B=; G=; R=; GB=; RB=; X=; fi
pass() { printf "  %s✅ %s%s\n" "$G" "$1" "$X"; }
fail() { printf "  %s❌ %s%s\n" "$R" "$1" "$X"; FAILED=1; }
note() { printf "  ·  %s\n" "$1"; }
hdr()  { printf "\n%s%s%s\n" "$B" "$1" "$X"; }

hdr "1. Locations"
echo "  app data  : $APP_SUPPORT"
echo "  database  : $DB"
echo "  recordings: $REC_DIR"

# Pick the meeting folder: an explicit id arg, else the most-recently-modified folder.
if [ "${1:-}" != "" ]; then
  MEETING="$REC_DIR/$1"
else
  MEETING="$(ls -dt "$REC_DIR"/*/ 2>/dev/null | head -1)"
fi
MEETING="${MEETING%/}"
if [ -z "$MEETING" ] || [ ! -d "$MEETING" ]; then
  hdr "Result"
  fail "No meeting folder under $REC_DIR — record + stop a meeting in the app first."
  exit 1
fi
ID="$(basename "$MEETING")"

hdr "2. Latest meeting: $ID"
echo "  $MEETING"

hdr "3. Package files present"
for f in transcript.json transcript.txt metadata.json pipeline.log status.json mic.wav; do
  if [ -f "$MEETING/$f" ]; then pass "$f"; else fail "$f MISSING"; fi
done
if [ -f "$MEETING/system.wav" ]; then pass "system.wav (call profile)"; else note "system.wav absent (in-person / mic-only — fine)"; fi

hdr "4. Pipeline finished cleanly"
if [ -f "$MEETING/status.json" ]; then
  PHASE="$("$PY" -c "import json,sys; print(json.load(open(sys.argv[1])).get('phase','?'))" "$MEETING/status.json" 2>/dev/null || echo '?')"
  if [ "$PHASE" = "done" ]; then pass "status.json phase = done"; else fail "status.json phase = '$PHASE' (expected 'done')"; fi
fi
if grep -q "packaging" "$MEETING/pipeline.log" 2>/dev/null; then pass "pipeline.log reached the 'packaging' phase"; else note "'packaging' not seen in pipeline.log"; fi
if grep -qi "traceback" "$MEETING/pipeline.log" 2>/dev/null; then fail "pipeline.log has a Python traceback — open it: $MEETING/pipeline.log"; else pass "no traceback in pipeline.log"; fi

hdr "5. Schema validation (the frozen ADR-005 contract)"
if [ ! -x "$PY" ]; then
  fail "pipeline venv not found at $PY — run: (cd pipeline && uv sync --group dev)"
else
  if ! "$PY" - "$SCHEMA" "$MEETING" <<'PYEOF'
import json, sys
from pathlib import Path
try:
    from jsonschema import Draft202012Validator
except ImportError:
    print("  jsonschema missing — run: (cd pipeline && uv sync --group dev)")
    sys.exit(1)
schema_dir, meeting = Path(sys.argv[1]), Path(sys.argv[2])
ok = True
for data_name, schema_name in [("transcript.json", "transcript.schema.json"),
                               ("metadata.json", "metadata.schema.json")]:
    dpath, spath = meeting / data_name, schema_dir / schema_name
    if not dpath.exists():
        print(f"  {data_name} missing"); ok = False; continue
    errors = sorted(
        Draft202012Validator(json.loads(spath.read_text())).iter_errors(json.loads(dpath.read_text())),
        key=lambda e: list(e.path))
    if errors:
        ok = False
        print(f"  {data_name}: {len(errors)} schema violation(s)")
        for e in errors[:5]:
            loc = "/".join(map(str, e.path)) or "(root)"
            print(f"       - {loc}: {e.message}")
    else:
        print(f"  {data_name} matches the frozen schema")
sys.exit(0 if ok else 1)
PYEOF
  then FAILED=1; fi
fi

hdr "6. Indexed in meetings.db"
if [ ! -f "$DB" ]; then
  fail "meetings.db not found — the app hasn't indexed any meeting yet."
elif ! command -v sqlite3 >/dev/null 2>&1; then
  note "sqlite3 not on PATH (unexpected on macOS) — skipping the DB query."
else
  ROW="$(sqlite3 -header -column "$DB" \
    "select id, company, type, status, speakerCount, diarized, syncState from meeting where id='$ID';" 2>/dev/null)"
  if [ -n "$ROW" ]; then
    pass "row found for this meeting:"
    echo "$ROW" | sed 's/^/        /'
  else
    fail "no row for id='$ID' in the meeting table"
    TOTAL="$(sqlite3 "$DB" "select count(*) from meeting;" 2>/dev/null || echo '?')"
    note "($TOTAL total rows in the table)"
  fi
fi

hdr "Result"
if [ "$FAILED" = 0 ]; then
  printf "  %s✅ ALL CHECKS PASSED — slice 5 works end to end.%s\n\n" "$GB" "$X"
else
  printf "  %s❌ SOME CHECKS FAILED — see the ❌ lines above.%s\n" "$RB" "$X"
  printf "     (If this is an OLD recording from before slice 5, that's expected — record a fresh one.)\n\n"
fi
exit "$FAILED"
