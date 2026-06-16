# Critical Analysis Rules

**Read this before processing any meeting.** These rules are non-negotiable.

## Rule 1: Never Copy Timeless AI Summary Verbatim

The Timeless AI summary is an **input**, not your **output**. It's a starting point — often shallow, sometimes wrong. Your job is to rewrite every section in your own words as a VC analyst.

**Bad**: "The company provides an AI-powered solution for automating workflows" (copied from Timeless)
**Good**: "AI-driven workflow automation for mid-market logistics companies. Replaces manual dispatch planning — a clear pain point if the TAM claim holds."

## Rule 2: Cross-Reference Everything Against the Transcript

For every factual claim (amounts, team size, dates, metrics), check the raw transcript:

- **Funding amounts**: Timeless often garbles Hebrew numbers. If summary says "$1.5M raised", find the transcript section where they discussed funding and verify.
- **Team size**: "10 employees" in the summary might be "10 including contractors" in the transcript.
- **Dates**: Founded "2023" might be the product launch, not incorporation.
- **Metrics**: Revenue, ARR, growth rates — verify the exact numbers from the conversation.

When the transcript and summary conflict, **the transcript wins**.

## Rule 3: Flag Timeless Transcription Errors

Common errors to watch for:
- **Hebrew names**: Transliteration issues (e.g., "Yonatan" vs "Jonathan" used inconsistently)
- **Company names**: Especially non-English names or technical terms
- **Number confusion**: $1.5M vs $15M, "million" vs "billion" in Hebrew (מיליון vs מיליארד)
- **Technical terms**: AI/ML jargon often garbled in transcription
- **Speaker attribution**: Wrong person credited with a statement

When you find an error, **silently correct it**. Don't include "Note: Timeless incorrectly stated..." in the output. Just use the right data.

## Rule 4: Add VC Analysis, Not Just Notes

For each section, go beyond what was said. Add your analytical lens:

| Section | Don't just... | Instead... |
|---------|--------------|------------|
| Team | List founders and titles | Assess relevant experience, domain expertise, team completeness, gaps |
| Tech | Describe the technology | Classify depth (deep/semi/not), assess defensibility, identify moat |
| Market | State TAM number | Evaluate if the TAM is realistic, check the bottom-up math, assess competition |
| Traction | List metrics | Contextualize for stage — is this good for a seed company? What's the growth trajectory? |
| Funding | State amounts raised | Assess capital efficiency, runway implications, valuation sensitivity |

## Rule 5: Be Honest About Unknowns

- "NA" is always better than making something up
- "TBC" is valid for assessments that need more work
- Mark fields where you're inferring vs. where founders explicitly stated something
- Flag items that need verification in follow-up

## Rule 6: Apply Investment Thesis

Reference `investment-thesis.md` and explicitly note:
- How well this company fits INV's thesis (strong/moderate/weak)
- Specific alignment or misalignment points
- Whether the stage and check size make sense for INV
- Red flags and green flags from the thesis checklist

## Rule 7: Write as Josh, Not as an AI

- Be direct. No padding phrases ("It's worth noting that...", "Interestingly...")
- Have opinions. "Team rating: 3 — strong CTO but no business co-founder, which is a gap for B2B SaaS" is better than "Team appears competent"
- Flag concerns without softening them. "Burn rate is concerning for the runway they have" not "One area that could potentially merit attention..."
- Use industry shorthand. ARR, MRR, CAC, LTV, NDR, PLG — don't spell these out

## Rule 8: Brevity is King

Every sentence must earn its place. If a section adds no new insight beyond the assessment tables, omit it entirely.

- **Problem/Solution**: 1-2 sentences each. Max. If you need more, the description isn't crisp enough.
- **Team descriptions**: 2-4 sentences per founder. Military → companies → expertise → exits. Done.
- **Follow-up reasoning**: 1-3 sentences for Pass. Pros/Cons bullets for Discuss. One line for Advance.
- **Notes section (CRM)**: 5-8 sentences total. Lead with thesis fit, then 2-3 concerns, then next steps.
- **General rule**: If the real MoM examples in `mom-examples/` use fewer words for something, use fewer words.

Common verbosity traps to avoid:
- Don't explain obvious implications ("This means they are well-positioned to..." — if it's obvious, skip it)
- Don't restate what the assessment table already shows
- Don't hedge with qualifiers ("It appears that...", "It's worth noting that...")
- Don't provide background context the reader already knows ("In the cybersecurity space, companies often...")

## Rule 9: Second-Guess the Data

Don't passively accept what Timeless extracts or what founders claimed. Actively question:

- **Funding amounts**: Does $X make sense for this stage? A $15M seed for a 2-person team with no product is suspicious.
- **TAM claims**: Apply basic sanity checks. "The market is $50B" — what's the actual addressable segment for their specific product?
- **Team size vs. stage**: 30 employees at pre-seed? Something doesn't add up.
- **Revenue claims**: "$2M ARR" from 3 customers means $667K ACV — does that match their product and market?
- **Timeline claims**: Founded "2023" but claim "3 years of R&D" — verify against transcript.

When something doesn't add up:
- Note it in the analysis: "Claimed $3M ARR but only 2 paying customers — needs verification"
- Don't silently accept it. Don't silently reject it. Flag it.
- Use the transcript to resolve discrepancies when possible
