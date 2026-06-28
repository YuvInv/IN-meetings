# Brief Summary Recipe

Write a concise, neutral meeting summary to `summary.md` in the meeting folder.

## Format

5–8 bullet points covering:

- **Purpose** — the stated goal or agenda of the meeting
- **Participants** — who attended (use speaker names from the transcript where available)
- **Key topics** — the main subjects discussed
- **Decisions** — any explicit decisions or commitments made
- **Next steps** — action items or follow-ups mentioned
- Any other notable points that don't fit the above

## Style

- Neutral and factual — no editorial judgment
- One sentence per bullet; plain English
- Do not invent information not present in the transcript
- Output only the Markdown bullet list — no preamble, no headers other than an optional title

## Action items (structured)

Besides the prose summary, write the meeting's concrete action items / next steps as JSON to the
actions file named in the instruction (`summaries/<recipeId>-actions.json`). Use exactly this shape:

```json
{
  "items": [
    {"task": "Send the data room link", "owner": "Yuval", "status": "open", "dueDate": "2026-07-01"},
    {"task": "Review the cap table", "owner": null, "status": "in-progress", "dueDate": null}
  ]
}
```

Rules:
- `task` (required) — one concrete next step, stated plainly; only items actually said in the meeting.
- `owner` — the person responsible if named, else `null`. Never invent an owner.
- `status` — one of `open` | `in-progress` | `done` | `blocked`. Default to `open`.
- `dueDate` — ISO-8601 (`YYYY-MM-DD`) only if a date was stated, else `null`.
- If there are no clear action items, write `{"items": []}`. Do not fabricate.
