# INV Meetings — Claude Code Memory

## Shared Instructions
@AGENTS.md

## Claude-Specific Features
- Use `/self-review` before creating PRs
- Use subagents for codebase exploration on large tasks
- Use `/codex:adversarial-review` before merging PRs with >200 lines changed
- When stuck on a bug for more than 2 attempts, use `/codex:rescue` for a fresh perspective

## Auto-Compact Priorities
When compacting context, preserve:
- File paths under investigation
- Confirmed root causes
- Remaining tasks from `HANDOFF.md`
- MCP server state and active connections
- Findings from subagent or Codex review runs

## MCP Servers Available
See `.agents/agents.json` for the canonical MCP list. Claude-only additions live in `.claude/settings.json`.
