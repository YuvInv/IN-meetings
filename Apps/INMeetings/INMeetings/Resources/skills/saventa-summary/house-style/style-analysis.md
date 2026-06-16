# IN Venture MoM Style Analysis

Statistical analysis of 16 Minutes of Meeting documents used to calibrate AI output length, tone, and structure.

**Companies analyzed (16):** Agensive, Avon.AI, Baz, BlueBricks, Callers, Deway, Firmwai (#1 and #2), Kelet, Lattica AI, Mermaid, Pandorian, Pfamos, Spiral, Spring AI, Viewz

---

## 1. Team Assessment

### Numeric Rating Usage

| Pattern | Count | Proportion | Companies |
|---------|-------|------------|-----------|
| With numeric rating | 9/16 | 56% | Agensive (3), BlueBricks (4), Deway (3.5), Firmwai#1 (4), Kelet (3.5), Pandorian (4) |
| Without numeric rating | 7/16 | 44% | Avon.AI, Baz, Callers, Firmwai#2, Lattica, Mermaid, Pfamos, Spiral, Spring AI, Viewz |

**Calibration rule:** Numeric ratings are common but NOT mandatory. Qualitative-only assessments are equally valid. When a number is given, it appears on a 1-5 scale.

### Word Count

- **Average:** ~17 words
- **Range:** 4-40 words
- **Target:** 1-3 sentences

### Tone Patterns

Team assessments are brutally direct. Standard data points include:

- **Personal observations:** "naive thinking", "colorful figure", "Smart but weird", "good hassler"
- **Meeting behavior:** "were not impressive in the meeting", "wasn't impressive during first part"
- **Paper vs. reality contrasts:** "On paper seem strong -- Uri raised $200M. In reality, he chose a market where has no clue"
- **External verification actions:** "to be vetted by reference", "check with Guy from Cheq"

**Calibration rule:** Informal, blunt language is the norm. "nice" can be pejorative. Meeting impressions are a first-class data point alongside credentials.

---

## 2. Follow-up Decision

### Distribution

| Decision | Count | Proportion | Companies |
|----------|-------|------------|-----------|
| Pass | 7 | 44% | Agensive, Deway, Lattica, Mermaid, Pfamos, Spring AI |
| Discuss | 3 | 19% | Firmwai#2, Kelet, Viewz |
| Advance | 6 | 37% | Avon.AI, Baz, BlueBricks, Callers, Firmwai#1, Spiral |

### Word Counts by Decision Type

| Decision | Avg Words | Range | Format |
|----------|-----------|-------|--------|
| Pass | ~15 | 5-30 | 1-3 sentences, brutally honest reason |
| Discuss | ~35 | -- | Pros/Cons format OR specific questions to resolve |
| Advance | ~12 | 1-25 | 1 sentence or just the word "Advance" |

**Calibration rules:**
- **Pass:** Always state the reason. Keep it short and direct. No softening language.
- **Discuss:** The longest format. Use Pros/Cons structure or list specific open questions that need answering before a decision.
- **Advance:** Can be as terse as a single word. No justification required (the positive assessment is implicit).

---

## 3. Assessment Table Fields

### Problem Field

- **Average:** ~18 words
- **Range:** 14-24 words
- **Style:** One sentence describing the pain point. Factual, no editorializing.

### Solution Field

- **Average:** ~16 words
- **Range:** 7-28 words
- **Style:** One sentence describing the product/approach. Technical but accessible.

### Tech Assessment

- **Average:** ~15 words
- **Range:** 5-30 words
- **Style:** Classification label + 1-sentence rationale
- **Classification labels used:** Deep tech, Semi-deep tech, Not deep tech
- **Example pattern:** "[Classification]. [One sentence explaining why.]"

### Market Field

- **Average:** ~5 words
- **Range:** 3-5 words
- **Style:** Just the vertical label. No elaboration.
- **Examples:** "Cyber Security", "Enterprise SaaS", "AI Infrastructure"

### Alignment Field

- **First meetings:** ALWAYS "TBC" (To Be Confirmed)
- **Calibration rule:** Never assign alignment on a first meeting. This is a hard rule.

### Influence Field

- **Style:** Just the round details (round name, amount, terms if known)
- **No analysis or commentary.**

---

## 4. Body Sections (Above Assessment Tables)

### Founder Descriptions

- **Word count:** 30-80 words per founder
- **Structure:** Military background -> Companies -> Domain expertise -> Exits
- **Style:** Factual, CV-like. No adjectives or opinions (opinions go in the Team assessment field, not here).

### Tech / Product Description

- **Word count:** 60-100 words
- **Style:** Most detailed body section. Factual and specific about what the product does, the architecture, and the technical approach. No opinion.

### Market / Problem in Body

- **Word count:** 30-50 words
- **Style:** Brief framing of the space. Sets context for the assessment table fields.

### Traction

- **Format:** ALWAYS bulleted list
- **Content:** Specific data points -- ARR, customers, pipeline, growth rate, logos
- **Style:** Numbers and facts only. No interpretation.

### Summary Section

- **First meetings:** ALWAYS empty placeholder (`<<Summary>>`)
- **Calibration rule:** Summaries are never written for first meetings. The assessment table IS the summary.

---

## 5. Key Style Rules (Aggregate)

These rules emerge from patterns across all 16 documents:

1. **Brevity is mandatory.** Every field has a tight word budget. Exceeding it signals poor calibration.
2. **Informal tone is correct.** Colloquial phrasing ("good hassler", "no clue") is standard, not an error.
3. **Opinions belong in assessment fields, facts belong in body sections.** Never mix them.
4. **Meeting impressions are first-class data.** How founders performed in the meeting is always noted alongside their credentials.
5. **Paper vs. reality is a valued contrast.** When credentials are strong but the meeting was weak (or vice versa), call it out explicitly.
6. **Action items go in Follow-up.** Specific next steps ("check with X about Y", "to be vetted by reference") are part of the decision, not a separate section.
7. **Tech classification is categorical.** Use deep/semi-deep/not-deep, then one sentence of rationale.
8. **Market is just a label.** 3-5 words max. No market sizing or analysis.
9. **Alignment is always TBC on first meetings.** No exceptions.
10. **Advance decisions need no justification.** Pass decisions always need a reason.

---

## 6. Length Calibration Summary

Quick reference for target output lengths:

| Field / Section | Target Length | Hard Max |
|----------------|--------------|----------|
| Problem | ~18 words | 25 words |
| Solution | ~16 words | 30 words |
| Team assessment | ~17 words | 40 words |
| Tech assessment | ~15 words | 30 words |
| Market label | ~5 words | 7 words |
| Follow-up (Pass) | ~15 words | 30 words |
| Follow-up (Discuss) | ~35 words | 50 words |
| Follow-up (Advance) | ~12 words | 25 words |
| Founder bio (body) | 30-80 words | 80 words |
| Tech description (body) | 60-100 words | 100 words |
| Market/Problem (body) | 30-50 words | 50 words |
| Traction (body) | Bulleted list | -- |
| Summary (first meeting) | Empty | 0 words |
