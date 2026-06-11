"""Deterministic entity post-correction — the P1-validated biasing mechanism (ADR-004).

Each entity has a canonical spelling + observed variants; variants are replaced as whole tokens.
Phase-2's context assembler fills the vocabulary; until then this runs as a no-op (empty vocab),
so the MVP ships unbiased but the hook is in place. Mirrors pipeline/benchmarks/postcorrect.py.
"""

from __future__ import annotations

import re


def correct(text: str, vocab: list[dict]) -> tuple[str, dict]:
    counts: dict[str, int] = {}
    for entry in vocab:
        canon = entry["canonical"]
        for variant in entry.get("variants", []):
            new, n = re.compile(re.escape(variant)).subn(canon, text)
            if n:
                text = new
                counts[canon] = counts.get(canon, 0) + n
    return text, counts
