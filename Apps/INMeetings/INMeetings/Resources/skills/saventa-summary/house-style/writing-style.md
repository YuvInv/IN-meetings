# IN Venture Writing Style Guide

Extracted from 16 real IN Venture MoM documents (Agensive, Avon.AI, Baz, BlueBricks, Callers, Deway, Firmwai x2, Kelet, Lattica AI, Mermaid, Pandorian, Pfamos, Spiral, Spring AI, Viewz). Follow these patterns exactly.

## Brevity Targets

Calibrated from 16 real IN Venture MoMs. These are DATA-DRIVEN limits:

| Field / Section | Target | Hard Max | Notes |
|----------------|--------|----------|-------|
| Problem (assessment table) | ~18 words | 25 words | 1 sentence |
| Solution (assessment table) | ~16 words | 30 words | 1 sentence |
| Team assessment | ~17 words | 40 words | 1-3 sentences |
| Tech assessment | ~15 words | 30 words | Classification + 1 sentence |
| Market label | ~5 words | 8 words | Just the vertical |
| Influence | Round details only | 15 words | |
| Follow-up (Pass) | ~15 words | 30 words | 1-3 blunt sentences |
| Follow-up (Discuss) | ~35 words | 50 words | Pros/Cons or specific questions |
| Follow-up (Advance) | ~12 words | 25 words | 1 sentence or just "Advance" |
| Founder bio (body) | 30-80 words | 80 words per founder | Military → Companies → Domain → Exits |
| Tech/Product (body) | 60-100 words | 100 words | Most detailed section |
| Market/Problem (body) | 30-50 words | 50 words | Brief framing |
| Summary | Empty for 1st meetings | 0 words for 1st | Never force a summary |
| CRM Notes section | 5-8 sentences | 8 sentences | Lead with thesis fit |

See `mom-examples/style-analysis.md` for the full statistical breakdown behind these numbers.

**The golden rule: if the real examples in `mom-examples/` use fewer words, use fewer words.**

Read `mom-examples/anti-patterns.md` to see common AI verbosity mistakes and their corrections.

## Tone

- **Brutally direct.** No hedging. "Naive thinking", "weird", "overconfident", "bad cap table" are all acceptable assessments.
- **Personality observations are expected.** "CEO is somewhat colorful figure", "Smart but weird" — this is how the team talks.
- **Sparse.** Don't pad empty sections. Use `NA` (not "N/A" or "Not discussed") for unknown fields.
- **Hebrew or English** — match the meeting language.

## Summary Section

The `<<Summary>>` section is typically **left empty** in first meetings. Don't force a summary if there's nothing meaningful to add beyond what the tables already show.

## Assessment Table Style

### Team Assessment

**Numeric rating is optional.** ~44% of real MoMs skip the number entirely. Use a number when you have a clear opinion; skip it when a qualitative assessment is more honest.

Format A (with rating): `{number} – {blunt assessment}`
Format B (no rating): `{blunt qualitative assessment}`

Real examples — with rating:
- `3 – domain experts with relevant experience but very naive thinking. Overconfident in their solution`
- `3.5 - Strong (technical aspect) founders with domain expertise. Running the biggest IL GenAI community. CEO is somewhat colorful figure.`
- `3.5 – while have impressive background, were not impressive in the meeting and didn't know market basics.`
- `4 – Seem very strong tech wise, domain experts. Both don't have GTM experience.`
- `4 – CEO seemed capable but to be vetted by reference. CTO seems strong. Both have C-level background in strong companies.`
- `4 – Strong domain experience, prior exit (Zest to WalkMe), complementary skillsets across product/sales/engineering.`

Real examples — no rating:
- `Sole founder. Smart but weird. Domain expert.`
- `Sole founder – serial entrepreneur with 2 exits. All team is based in the US.`
- `Strong team, Guy is 3rd timer with a successful exit. Strong investors.`
- `Impressive CEO. Sole founder. CTO joined post Seed.`
- `Capable team CEO (Talpiot program/ 8200) – seemed to grow and improve from one year ago.`
- `On paper seem strong – Uri raised $200M. In reality, he chose a market where has no clue and seems like he didn't do proper research.`
- `Very strong founder market fit. Weak team ("nice"). CEO doesn't seem to have any GTM understanding. Bad storytelling.`
- `Good team but not top. CEO is a good hassler and sales person but with no global experience in the team.`
- `Strong tech team. No commercial experience in core founders. Added a 3rd founder / advisor for 15% equity.`
- `On paper it seems strong team. Itamar wasn't impressive during the first part of the meeting. Good founder market fit.`

Key rules:
- **Meeting impression is a valid and expected data point** — how did the founder perform in the actual meeting?
- **"On paper vs reality" contrast** is a valued pattern when credentials don't match meeting impression
- Always note gaps: "no GTM experience", "sole founder", "no business co-founder"
- Include personality observations: "naive thinking", "colorful figure", "Smart but weird", "good hassler"
- Informal language is normal: "nice" in quotes = not impressive enough (pejorative)
- Can include action items: "to be vetted by reference", "check with Guy from Cheq about the CEO"
- Ratings use integers or .5 (1-5 scale) when used

### Tech Assessment

Format varies — classification word + 1 sentence rationale:
- `4 – Deep domain expertise. Closing the loop with real HW is something that will differentiate them from other SW development solution.`
- `Not deep. Systematic analysis of failures to get quick root cause.`
- `Not deep 400 integrations, including legacy systems. Customized workflows per customer.`
- `Deep tech – requires expertise in cryptography and GPU optimization.`
- `AI-native agent-based architecture. Inside-out approach (starts from business assets, works backwards to entry points).`
- `Combination of cyber (protocol reverse-engineering) and AI (algorithmic analysis)`
- `Semi-deep. Agent-based infrastructure automation with policy enforcement layer.`
- `Proprietary tooling layer on top of LLMs. Custom code interpreters and semantic search from security background.`
- `Not Deep but comprehensive. Ability to ingest data in a generic way and normalize it.`
- `Built agent-agnostic wrapper enabling pre/post processing and data manipulation to control agent behavior without accessing internal logic.`
- `TBC` (valid when insufficient data — used for Mermaid)
- `Agentic solution` (valid ultra-brief — used for Pfamos)

### Market

Brief — just the market vertical (3-8 words max):
- `Cyber ASM`
- `GenAI agents`
- `FW development.`
- `Digital banking for community banks`
- `SW – Dev tools. Management tool, not single developer.`
- `GTM / CX automation. focused on specific B2C verticals`
- `Product adoption/analytics enablement.`
- `AI agent management`
- `Enterprise fraud prevention`
- `Financial data management`
- `Autonomous cloud operations for enterprises with 200+ developers.`
- `code review for engineering teams`

### Alignment

Almost always `TBC` for first meetings. Only filled if thesis fit is immediately obvious.

### Influence

Round size and key terms. Can include investor info when notable:
- `$6M seed`
- `$5-6M Seed round`
- `$8-10M Seed`
- `$8M Seed round`
- `$2.2M+ out of $8M Seed @ $15M Pre.`
- `$10M A round @ $35M Pre led by Flashpoint.`
- `A round $15-20M`
- `$4M Safe round – $2 from IBEX (existing investors)`
- `$3-5M`
- `Raising $12M round`
- `$30M post seed round of $5-10M. $3.5 already committed.`
- `TBC` (valid when exploring, no concrete round yet)

## Follow-Up Decision

**Uses "Advance" — NOT "Continue"**. Three options: Pass / Discuss / Advance.

### Pass examples (7 real):
- `Pass: Naïve approach trying to change completely how cyber analysts work, not very impressive despite good problem understanding. Not competitive with Cyber funds.`
- `Pass: Sole founder. If works and hyperscale's believe there's a market will likely get acquired quickly. Bad CAP table.`
- `Pass : Market and our ability to help`
- `Pass: Team didn't impress. Market seems niche. Not competitive at all.`
- `Pass: Team was not strong. Building a category of their own with the belief this is a huge current problem (no competitors). Not only building their own category the buyer (CRO) adds complexity. Requesting a way too big ticket.`
- `Pass: Uri couldn't convince there's a real problem. The market is already crowded with new startups already well funding in the states (with a different approach to the solution).`

### Discuss examples (3 real):
- `Discuss: Pros: Domain experts (mostly network perspective), Nice traction for their stage (3 pilots with design partners). Cons: Not very deep tech. It can be easily expanded to by EVAL tools which is still unsolved. Small market now. CEO is debatable.`
- `Discuss – check with Guy from Cheq about the CEO.`
- `Discuss: Itamar was not Impressive during most of the meeting. Not sure how much validation was done. Not sure if they have a good market understanding. Seem like a real problem`
- `Discuss: Nice execution in Israel (# of customers and ACV) but only single customers in the US. Unconvincing GTM strategy on how to with the US market. Product makes sense, could have some tech depth.`

### Advance examples (6 real):
- `Advance – get more materials and look into the opportunity. Nice traction, very easy integration into banks (long contracts), 45 customers. Small overall market, can become a medium size company quickly.`
- `Advance – Chen made a positive impression. Showing nice traction but still too much focus in the Israeli market.`
- `Advance: Drill down deeper. Strong team, a bit stuck so can't raise in the US. Big potential if successful.`
- `Advance: Seems like a real problem highly emphasized by GenAI. Credible team with what seems to be poor execution.`
- `Advance` (can be just one word if obvious)

Note: Advance often includes brief reasoning — it's not always just the word. 4/6 real Advance decisions have 1-2 sentences of context.

Key rules:
- Pass reasons are blunt — 1-3 sentences
- Discuss uses Pros/Cons format or flags specific questions
- Advance includes next steps when applicable
- Never use "Continue" — always "Advance"

## Founder Descriptions

Factual career history. 2-4 sentences per founder. Pattern: Military → Companies → Domain → Exits.
No adjectives about "leadership style" or "strategic vision" — save personality for the Team assessment field.

Real examples:
```
CEO – Itamar Weiss. Talpiot graduate. VP R&D @ Sight diagnostics, free lancer. Early team member @ Alooma (now Google).
CTO – Omer Bartal. firmware development across hundreds of projects. Deep expertise in embedded systems, drivers, IoT platforms, microcontroller families (STM32, etc.). Director @Prospera.
```

```
CEO – Guy Eizenkot: 8200 Unit intelligence background. Co-founded Portscale (unsupervised ML for security analytics, sold to RSA 2018). Co-founded Bridgecrew (infrastructure security, sold to Palo Alto Networks early 2021). Served as GM at Palo Alto, built team from 20 to 200 employees, grew business unit to ~$100M ARR.
```

```
CEO Nimrod Ron – Shaldag in IDF. Real Estate investor. Owner of failed startup. Working on Callers for 6.5 years.
CTO - Raanan Hacham: Joined post-seed. Has 9.99% non dilutive until reaches same holding as CEO.
```

```
CEO –Shawn Melamed: Serial fintech entrepreneur based in New Jersey. Founded first startup at 26 building stock/options transaction reconciliation platform for banks; sold to major institutions including Chase and Morgan Stanley (2012). Second company built microwave market data networks between Chicago/New York/Toronto; sold to TMX Group (2014). Spent 5 years at Morgan Stanley (2014-2019) as Head of Technology Business Development & Innovation Office.
```

```
CEO Almog Baku entrepreneur with single very small exit as CTO - Rimoto (2015-2018)
Founder & CEO at Natun (2020-2022)
Founded Gen-AI Israel community
ML/AI infrastructure consulting background
```

Note: Format is loose — some use bullet points, some are prose. Content matters more than formatting. Include failures and context (e.g., "Owner of failed startup", "single very small exit") — honesty is valued.

## Problem/Solution Table

- Problem: 1-2 sentences. Specific pain point, not generic industry problem.
- Solution: 1-2 sentences. What the product actually does.
- Established: Year or "Month Year" (e.g., "Jan 2026", "Sep 2025", "Q1 2025")
- Stage: Brief (e.g., "Seed", "Pre-seed / Seed")

## Funding Table

Format: `Date | Amount | Type | Terms | Participants`
- Leave rows empty if unknown
- Amount includes currency and unit: "$3M", "$42M"
- Terms: post-money valuation or cap+discount
- Participants: investor names

## Number Formatting

- Funding: "$6M", "$1.5M", "$500K"
- Valuation: "$23M Post", "$30M post-money", "$15M Pre"
- ACV: "$50K", "$200K/month"
- ARR: "$2.2M ARR"
- Team size: "6", "Founders" (if just founders), "20"
- TAM: "$200Bn" or "TBC" — never fabricate

## What NOT to Do

- Don't fill Alignment — use "TBC" for first meetings
- Don't write a Summary if there's nothing to add
- Don't use "Continue" — use "Advance"
- Don't use "N/A" — use "NA"
- Don't soften assessments — if the founders are naive, say so
- Don't pad sections — empty is fine
- Don't use "innovative", "cutting-edge", "state-of-the-art", "leveraging"
- Don't spell out acronyms (ARR, ACV, GTM, ICP, TAM, SAM)
- Don't restate what the assessment tables already say — if it's in the table, it doesn't need prose
- Don't explain industry background the reader already knows
- Don't write transitions or warm-up sentences — start with the fact
