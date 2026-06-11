#!/usr/bin/env python3
"""P1: deterministic entity post-correction (the recommended primary biasing mechanism).

The ivrit fine-tune renders most Hebrew proper nouns well but mangles a few
(esp. code-switched English names like "IN Venture") and does NOT reliably honor
initial_prompt biasing. Instead of betting on the prompt, we correct the ASR
output against the context assembler's vocabulary: each entity has a canonical
spelling + known/observed variant spellings, replaced as whole tokens.

This is deterministic, debuggable, and gives the Claude skills the canonical
spellings they want (e.g. "Prelligence", "IN Venture", founder names).

Usage: python3 postcorrect.py <transcript.txt> <vocab.json>
  vocab.json: [{"canonical": "...", "variants": ["...", "..."]}, ...]
"""
import json
import re
import sys
from pathlib import Path


def correct(text: str, vocab: list[dict]) -> tuple[str, dict]:
    counts: dict[str, int] = {}
    for entry in vocab:
        canon = entry["canonical"]
        for variant in entry.get("variants", []):
            # whole-token replace; variants may contain spaces/punct (Hebrew has no word boundary \b for some scripts)
            pattern = re.compile(re.escape(variant))
            new, n = pattern.subn(canon, text)
            if n:
                text = new
                counts[canon] = counts.get(canon, 0) + n
    return text, counts


def main(argv: list[str]) -> None:
    text = Path(argv[0]).read_text(encoding="utf-8")
    vocab = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    corrected, counts = correct(text, vocab)
    out = Path(argv[0]).with_suffix(".corrected.txt")
    out.write_text(corrected, encoding="utf-8")
    print(f"wrote {out}")
    print("replacements:", counts or "(none)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1:])
