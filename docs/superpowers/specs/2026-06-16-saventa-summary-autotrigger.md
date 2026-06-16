# Saventa-summary auto-trigger — design (2026-06-16)

**Status:** approved direction (Yuval). **Scope:** generate + surface + sync the summary. **CRM posting
to Sevanta is OUT — on hold.**

## Goal

When a meeting finishes, automatically produce IN Venture's short, house-style deal summary from the
on-disk context package, show it in the dashboard, and sync it to Drive — **with no per-machine skill
install** (the app carries the recipe + the house style).

## Decisions (settled)

- **Engine:** headless Claude Code (`claude -p`). Not the raw API (would rebuild the skill), not the
  Claude chat app (no auto-push into a conversation).
- **The app owns the recipe** — bundled with the app, not a globally-installed skill. Removes the
  per-machine install, the plugin-overwrite risk, and version drift. For a pure-instructions skill
  (no MCP/API) the install machinery buys nothing.
- **Full house style bundled** — the saventa recipe + the non-CRM `vc-context` files.
- **Auto-on-finish is safe** (it only writes a file — no external action), so it runs automatically;
  plus a manual re-run button.
- **No CRM** (dropped, not surfaced again).

## The flow

```
pipeline "done" (JobBridge.indexCompletedPackage)
  → index package into SQLite                         [exists]
  → Drive-sync the package                            [exists]
  → kick SummaryRunner  (async, non-blocking)         [NEW]
       → claude -p (recipe+house-style as system prompt) over the meeting folder
       → writes <folder>/summary.md
       → state=done, capture session id → upload summary.md to Drive → ping dashboard
```

The package syncs immediately; the summary lands a moment later. Never blocks recording or the pipeline.

## Components

### 1. Bundled house-style recipe (the app's source of truth)
- Vendored in the repo at `skills/saventa-summary/`:
  - `recipe.md` — the saventa-summary SKILL.md **adapted for bundling**: local-folder mode is the only
    path; the template + output rules are kept verbatim; the "read the vc-context skill files"
    references become "your house-style context is included in these instructions" (we **inline**, we
    don't let Claude read files).
  - `house-style/` — a snapshot of the **non-CRM** vc-context: `critical-analysis.md`,
    `writing-style.md`, `investment-thesis.md`, `josh-preferences.md`, `anti-patterns.md`,
    `example-summary.md`, `style-analysis.md`. (Excludes `sevanta-api-reference.md` / `crm-mappings.md`.)
- **Bundled into `.app/Contents/Resources/`** (like the VAD model), so it ships with the app.
- This is a **vendored snapshot** of `~/repos/claude-skills/vc-context` — updating the app's style is a
  deliberate re-copy + rebuild (keeps team builds self-contained; no dependency on a teammate's local
  skills). The original installed skill can stay for Yuval's manual `/saventa-summary` use.

### 2. `SummaryRunner` (Core, mirrors `JobBridge`)
- `run(meetingID:, folder:)`:
  - assemble the **system prompt** = `recipe.md` + all `house-style/*.md` (clear separators).
  - spawn: `claude -p "Summarize the meeting package at <folder> and write summary.md there."
    --append-system-prompt <assembled> --permission-mode acceptEdits --output-format json`
    - `acceptEdits` (or scoped `--allowedTools Read,Write,Glob`) → reads the package + writes
      `summary.md` with **no interactive prompt**, and nothing else (no network/MCP).
    - `--output-format json` → captures the **session id** (so "ask a follow-up about this meeting" can
      `--resume` later) + the result.
  - **env:** `PATH` includes `~/.local/bin` (where `claude` lives) — same trick `JobBridge` uses for
    `whisper-cli`; inherits the user's Claude auth/config. **cwd:** the meeting folder.
  - **capture:** stdout/stderr → per-meeting `summary.log` (durable trail, like `pipeline.log`).
  - **concurrency:** serial (one run at a time) — observable, gentle on Claude usage.
  - done → `summaryState=done` + session id → re-upload `summary.md` to Drive → notify.
  - fail → `summaryState=failed` + error → notify. `claude` not found → graceful (settings hint).

### 3. Schema — `MeetingStore` migration **v3**
- Adds `summaryState` (`running`/`done`/`failed`), `summaryError`, `summarySessionId` to `MeetingRecord`.
  `SummaryRunner` updates them; the dashboard reads them.

### 4. Drive
- `DriveSync.textFileNames += "summary.md"` (syncs with the package). After a summary completes,
  re-upload just `summary.md` (the `reuploadPackageFile` path we already built).

### 5. Dashboard "Summary" panel (`MeetingDetailView`, top of the detail)
- **running** → "Generating summary…" spinner.
- **done** → the saventa note in a monospace, paste-ready block + **Copy**.
- **failed** → the error + **Retry**.
- **not run** → a **Summarize** button (manual trigger / re-run).
- Reloads on a `summaryDidFinish` notification (same pattern as `jobBridgeDidFinish`).

### 6. Settings (Settings ▸ Recording)
- "**Auto-summarize finished calls**" toggle (default **on**), in `CaptureSettings`.
- Manual **Summarize** button per meeting (re-run, or when auto is off).

### 7. Trigger point
- `JobBridge.indexCompletedPackage`: after index + `driveBackup`, kick `SummaryRunner` when auto is on
  and `claude` is available. Non-blocking, best-effort.

## Error handling / risks
- `claude` not found / not logged in → graceful failure + a settings hint. **Onboarding:** every Mac
  needs `claude` installed + logged in — the *only* remaining per-machine dependency (no skill install).
- **Live-verify (can't unit-test):** that `claude -p` reliably runs the bundled recipe **and** writes
  `summary.md` headless under `acceptEdits`.
- Failures are non-fatal — the transcript/package still exist; the panel offers a retry.

## Out of scope (this round)
- CRM posting to Sevanta — on hold.
- Meeting-type routing (skip all-internal / HR) — later refinement; M1 summarizes all `call` meetings
  with the off-switch.
- MoM / enrich chaining — later.

## Manual test plan
1. Record a call → after the pipeline finishes, `summary.md` appears in the folder; the dashboard shows
   the summary; Drive has `summary.md`.
2. `claude` offline / logged out → graceful "summary failed" + Retry; recording + transcript unaffected.
3. Toggle auto **off** → no auto-summary; the per-meeting **Summarize** button still works.
4. Re-run on a meeting that already has a summary → overwrites cleanly.
