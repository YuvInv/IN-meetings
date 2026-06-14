"""Deterministic entity post-correction — the P1-validated biasing mechanism (ADR-004).

Each entity has a canonical spelling + observed variants; a variant is replaced only when it appears
as a whole token (not inside a larger word). Phase-2's context assembler fills the vocabulary; until it
does, an empty vocab makes this a no-op. Mirrors pipeline/benchmarks/postcorrect.py.
"""

from __future__ import annotations

import re

# A "token char" for boundary purposes: any word char (incl. Hebrew), plus the apostrophe/geresh and
# gershayim that occur *inside* Hebrew transliterations (e.g. נדוויינצ'ר). A variant matches only when
# it is not flanked by one of these — i.e. it stands as a complete token.
_TOKEN = r"[\w'’״׳]"


def correct(text: str, vocab: list[dict]) -> tuple[str, dict]:
    counts: dict[str, int] = {}
    for entry in vocab:
        canon = entry["canonical"]
        for variant in entry.get("variants", []):
            if not variant:
                continue
            pattern = re.compile(rf"(?<!{_TOKEN}){re.escape(variant)}(?!{_TOKEN})")
            new, n = pattern.subn(canon, text)
            if n:
                text = new
                counts[canon] = counts.get(canon, 0) + n
    return text, counts
