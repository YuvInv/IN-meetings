#!/usr/bin/env python3
"""P1: compare proper-noun rendering across transcript variants.

Counts correct vs error spellings of known entities in each transcript .txt,
to evaluate whether initial_prompt biasing helps/hurts proper-noun accuracy.

Usage: python3 compare_terms.py results/<a>.txt results/<b>.txt ...
"""
import sys
from pathlib import Path

# (label, substring, is_error) — tuned for the Prelligence eval meeting.
TERMS = [
    ("אלגוליון Algolion ✓", "אלגוליון", False),
    ("אלכוהוליון (alcohol-ion) ✗", "אלכוהוליון", True),
    ("פרליג'נס Prelligence ✓", "פרליג'נס", False),
    ("ג'נרל מוטורס GM ✓", "ג'נרל מוטורס", False),
    ("טכניון Technion ✓", "טכניון", False),
    ("סאטק Satec ✓", "סאטק", False),
    ("מגנטון Magneton ✓", "מגנטון", False),
    ("אין וונצ'ר IN-Venture ✓", "אין וונצ'ר", False),
    ("נדוויינצ IN-Venture ✗", "נדוויינצ", True),
]


def main(paths: list[str]) -> None:
    texts = {Path(p).stem: Path(p).read_text(encoding="utf-8") for p in paths}
    cols = list(texts)
    print(f"{'entity':<30}" + "".join(f"{c[:14]:>16}" for c in cols))
    for label, sub, is_err in TERMS:
        marker = "  ✗ERR" if is_err else ""
        counts = "".join(f"{texts[c].count(sub):>16}" for c in cols)
        print(f"{label:<30}{counts}{marker}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1:])
