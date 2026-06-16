# MoM Anti-Patterns — What NOT to Write

Common AI-generated verbosity patterns that make MoMs too long. Compare with the real examples in this directory.

## 1. Over-Explaining the Obvious

**Bad (AI-generated):**
```
Problem: In today's rapidly evolving cybersecurity landscape, organizations face an increasingly complex threat environment. Attack surface management has become a critical concern as companies expand their digital footprint across cloud, on-premise, and hybrid environments. Traditional security tools often fail to provide comprehensive visibility into all potential entry points, leaving significant gaps in organizational security posture.
```

**Good (real MoM):**
```
Problem: Organizations run multiple offensive security engagements annually but lack unified, actionable risk visibility. Current tools provide fragmented findings without business context or validated attack paths.
```

**Rule**: 1-2 sentences. Name the pain, not the industry background.

## 2. Restating Assessment Table Content in Text

**Bad:**
```
The team is rated 3.5 out of 5. The founders bring strong technical backgrounds and domain expertise. The CEO has experience running AI-related communities in Israel and demonstrates strong networking capabilities. The CTO has deep technical skills in the relevant domain.
```

**Good:**
```
3.5 - Strong (technical aspect) founders with domain expertise. Running the biggest IL GenAI community. CEO is somewhat colorful figure.
```

**Rule**: The assessment IS the text. Don't paraphrase it elsewhere.

## 3. Padding with Qualifiers and Transitions

**Words to delete on sight:**
- "It's worth noting that..."
- "Interestingly..."
- "It appears that..."
- "In terms of..."
- "With regard to..."
- "One key aspect is..."
- "Looking at the broader picture..."
- "From a strategic perspective..."
- "It should be mentioned that..."

**Rule**: Start with the fact. No warm-up.

## 4. Verbose Follow-Up Decisions

**Bad:**
```
Follow-up Decision: After careful consideration of the team's capabilities, market positioning, and alignment with our investment thesis, we recommend continuing the evaluation process. The company demonstrates promising technology in an interesting market, though there are several areas that warrant further investigation, including the competitive landscape, revenue trajectory, and customer acquisition strategy.
```

**Good:**
```
Pass: Naïve approach trying to change completely how cyber analysts work, not very impressive despite good problem understanding. Not competitive with Cyber funds.
```

**Rule**: Pass = 1-3 blunt sentences. Discuss = Pros/Cons bullets. Advance = next steps or just "Advance".

## 5. Generic Market Descriptions

**Bad:**
```
Market: The global cybersecurity market is projected to reach $350 billion by 2028, growing at a CAGR of 12.4%. Within this market, the attack surface management segment represents a significant opportunity, particularly as organizations continue their digital transformation journeys and adopt cloud-native architectures.
```

**Good:**
```
Market: Cyber ASM
```

**Rule**: The market field is a label, not an essay. Put analysis in Notes if needed.

## 6. Copying Timeless AI Summary Phrasing

Common Timeless phrases that should NEVER appear in MoMs:
- "The company offers a comprehensive solution for..."
- "The founders discussed their vision for..."
- "Key highlights from the meeting include..."
- "The team presented their approach to..."
- "During the conversation, it was mentioned that..."

**Rule**: Rewrite everything in Josh's voice. Direct, opinionated, no presentation-speak.

## 7. Fabricating Analysis Where None Exists

**Bad:**
```
Alignment: The company shows moderate alignment with IN Venture's investment thesis, particularly in the B2B SaaS and developer tools space. The seed-stage focus and Israeli headquarters are positive indicators. However, the relatively early stage of the product and limited traction suggest that continued monitoring would be prudent before committing resources.
```

**Good:**
```
Alignment: TBC
```

**Rule**: If you don't have enough data, write TBC or NA. Never fill space with speculation dressed as analysis.

## 8. Inflating Founder Descriptions

**Bad:**
```
CEO – John Smith brings over 15 years of extensive experience in the technology sector, having held various leadership positions at several prominent organizations. His career trajectory demonstrates a consistent pattern of innovation and strategic thinking, particularly in the areas of enterprise software and cloud computing. He previously served as VP of Engineering at a well-known technology company, where he led a team of 50+ engineers in developing cutting-edge solutions. His educational background includes a degree from a prestigious university, and he is known for his collaborative leadership style and deep understanding of market dynamics.
```

**Good:**
```
CEO – Itamar Weiss. Talpiot graduate. VP R&D @ Sight diagnostics, free lancer. Early team member @ Alooma (now Google).
```

**Rule**: Military → companies → domain → exits. 2-4 sentences. No adjectives about "leadership style."
