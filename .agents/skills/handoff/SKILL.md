---
name: handoff
description: Produce or update HANDOFF.md when the user signals a switch between Claude Code and Codex CLI (e.g., "handoff", "switch to codex", "switch to claude", "I'm out of credits", "credits done", "switching agents") or at the end of a major task phase.
---

# Handoff

## When to trigger

- User says "handoff", "switch to codex", "switch to claude", "continue with codex", "continue with claude"
- User says "I'm out of credits", "credits done", "switching agents"
- End of a major task phase when the other agent will take over

## Steps

1. Create or update `HANDOFF.md` in the project root (overwrite prior contents — this is not a log).
2. Fill in each section:
   - **Outgoing Agent**: which tool you are
   - **Date**: today's date (YYYY-MM-DD)
   - **Current State**: what got done this session
   - **Files Changed**: with brief descriptions
   - **Open Questions**: unresolved ambiguities
   - **Remaining Tasks**: checkboxes
   - **Known Issues**: bugs found but not fixed
   - **Context**: failed approaches, gotchas the next agent should know
3. Stage the file: `git add HANDOFF.md` (do NOT commit)
4. If `DECISIONS.md` was updated this session, mention that in the handoff.
5. Summarize to the user: what was done, what's left, any decisions logged.

## HANDOFF.md structure

See the project's own `HANDOFF.md` (created by the `setup-dual-agent` skill) for the canonical template. The structure is: Outgoing Agent / Date / Current State / Files Changed / Open Questions / Remaining Tasks / Known Issues / Context.

## Red flags (stop and ask)

- Branch has uncommitted changes across many files unrelated to the task → flag to the user before handoff
- Tests are currently failing → note this prominently in "Known Issues"
- You made an architectural decision but did not log it in `DECISIONS.md` → log it before writing HANDOFF.md
