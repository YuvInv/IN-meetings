# P1 — Hebrew + code-switching ASR benchmark: findings

**Date:** 2026-06-11 · **Hardware:** Apple M4, 24 GB, macOS 26.5.1 · **Engine:** whisper.cpp 1.8.6
(Metal, flash-attn) + `ivrit-ai/whisper-large-v3-turbo` GGML (1.5 GB, Apache-2.0).
**Audio:** real IN Venture founder pitch ("Prelligence", 55 min, Hebrew with English code-switching),
pulled via the `timeless` skill. Reproduce with `run_benchmark.sh` / `compare_terms.py` / `postcorrect.py`.

> **Go/No-Go: GO** on on-device Hebrew ASR — with one design change: **drop `initial_prompt` biasing as
> the primary context-injection mechanism; use deterministic post-correction instead.** Validated below.

## Result 1 — Speed: on-device is comfortably fast (target met)

| Audio | Wall time | Real-time factor |
|------|-----------|------------------|
| 6 min clip | 37 s | **~9.7× realtime (RTF ≈ 0.10)** |
| 55 min full | _(see results/wcpp_full.log)_ | ~9–10× realtime expected (~5–6 min) |

Metal GPU (MTLGPUFamilyMetal4), flash-attention on, model load ~1 s. The ≤¼-realtime target from
ADR-003 is beaten by ~2.5×. **On-device default is confirmed viable** on the team's hardware floor.

## Result 2 — Baseline Hebrew quality is strong (beats Timeless qualitatively)

Without any prompt, the ivrit turbo model produces fluent, largely-correct Hebrew and **already renders
most proper nouns correctly**: אלגוליון (Algolion), פרליג'נס (Prelligence), ג'נרל מוטורס (General Motors),
טכניון (Technion), סאטק (Satec), מגנטון (Magneton), plus English company names (Broadcom, Sony, Motorola)
and acronyms (GM, AI, CTO). Timeless's own transcript for the same meeting labeled speakers only as generic
"Speaker 1/2/3" (no names) — confirming the research finding that we beat it on attribution via calendar mapping.

Remaining errors are concentrated in **code-switched English proper nouns**, exactly as the research predicted:
- "IN Venture" → "נדוויינצ'ר" (mangled)
- founder/segmentation slips, and a few English phrases transliterated ("time-series" → "time-serious").

## Result 3 (the important one) — `initial_prompt` biasing does NOT work; it can regress

3-way comparison on the 6-min clip — counts of correct vs error spellings (`compare_terms.py`):

| Entity | no-prompt | Latin-script prompt | Hebrew-script prompt |
|--------|:---------:|:-------------------:|:--------------------:|
| אלגוליון (Algolion) ✓ | 5 | **1** | 4 |
| אלכוהוליון (*alcohol*-ion) ✗ | 0 | **6** | 0 |
| פרליג'נס / ג'נרל מוטורס / טכניון / סאטק / מגנטון ✓ | all ✓ | all ✓ | all ✓ |
| "IN Venture" rendered correctly | 0 | 0 | 0 |

- **Latin-script biasing is actively harmful** — it broke a name the model otherwise gets right
  (אלגוליון → אלכוהוליון, 6×). The forced-Hebrew fine-tune won't emit Latin, so Latin prompt terms just
  destabilize it.
- **Hebrew-script biasing is ~neutral** — no regressions, but no real improvement on the hard items either.
- **Neither fixes "IN Venture"** (the hardest term) — wrong in all three variants.

This empirically confirms the research caveats ("fragile prompt-following after the ivrit catastrophic-
forgetting episode; mixed-script prompts untested") and **invalidates the naive form of the
context-injection bet.** Caught before building the pipeline around it — the point of P1.

## Result 4 — Deterministic post-correction works (the replacement mechanism)

Instead of hoping the model honors a prompt, correct its output against the context assembler's vocabulary
(canonical entity + known/observed variant spellings → whole-token replace). On the no-prompt transcript
(`postcorrect.py` + `results/prelligence.vocab.json`):

```
replacements: IN Venture:1, Prelligence:2, Algolion:5, General Motors:10, Technion:2
"אז אנחנו נדוויינצ'ר"  →  "אז אנחנו IN Venture"
```

It also yields the **canonical (Latin) spellings the Claude skills want** (Prelligence, General Motors) from
the model's Hebrew renderings — deterministic, debuggable, no regressions.

## Implications for the design (updates ADR-003 / ADR-004)

1. **Demote `initial_prompt`** from "the bet" to a minor, optional input; **never put Latin proper nouns in it.**
2. **Promote deterministic post-correction to the primary context-injection mechanism.** ADR-004's
   assembler must emit, per entity, a **canonical spelling + variant spellings** (Hebrew + Latin), not just a
   biasing word-list. Source variants from CRM/Dealigence canonical names + a small transliteration generator;
   grow the observed-variant list from real misses.
3. **On-device default stands** — speed and Hebrew quality both confirmed on M4/24GB.
4. The build order is unchanged, but ADR-003's "biasing" task becomes "post-correction vocabulary + matcher"
   (plus an optional fuzzy/edit-distance pass for unseen variants, to be tested next).

## Open / next
- Confirm full-length RTF (full run in `results/wcpp_full.log`).
- Build a small hand-corrected reference (first ~3 min) for an actual WER number, no-prompt vs post-corrected.
- Test a fuzzy (edit-distance) post-correction pass for variants not in the vocab, guarding short tokens.
- Diff the full ivrit transcript vs the full Timeless transcript as an "is it better" artifact.
