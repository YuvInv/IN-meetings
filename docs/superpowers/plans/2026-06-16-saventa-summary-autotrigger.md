# Saventa-summary auto-trigger — implementation plan (2026-06-16)

Executes the approved spec [`2026-06-16-saventa-summary-autotrigger.md`](../specs/2026-06-16-saventa-summary-autotrigger.md).
Branch: `feat/saventa-summary-autotrigger` (off `main`). **CRM posting is OUT — on hold.**

## Integration map (verified by codebase scan, 2026-06-16)
- **Trigger:** `JobBridge.indexCompletedPackage(at:)` — after `driveBackup.syncIfConfigured`.
- **Notification:** reuse `.jobBridgeDidFinish`; add `.summaryDidFinish`.
- **Store:** `MeetingStore` migrations v1/v2 present → add **v3**; `MeetingRecord` gains summary fields.
- **Drive:** `DriveSync.textFileNames` (+`summary.md`); single-file re-upload = `DriveAuth.reuploadPackageFile`.
- **Settings:** `CaptureSettings` (UserDefaults-backed `@Observable`) → add `autoSummary` (default **on**).
- **UI:** `MeetingDetailView` header area → Summary panel; `RecordingStore` already reloads on notification.
- **Resources:** app auto-bundles `Apps/INMeetings/INMeetings/Resources/` (XcodeGen); add `skills/saventa-summary/`.

## Tasks (each: implement → test/build → gate before the next)
1. **Vendor the recipe + house-style** into `Resources/skills/saventa-summary/`: `recipe.md` (the SKILL.md
   adapted — local-folder-only path, house-style referenced as "included below" since the runner inlines it)
   + `house-style/*.md` (the 7 non-CRM vc-context files). **Gate:** files present + recipe coherent.
2. **MeetingStore v3** — migration adds `summaryState`/`summaryError`/`summarySessionId`; `MeetingRecord`
   gains them; `updateSummaryState(id:state:error:sessionId:)`. TDD. **Gate:** `swift test`.
3. **CaptureSettings.autoSummary** (default `true`). TDD. **Gate:** `swift test`.
4. **SummaryRunner** (Core) — assemble the system prompt (recipe + house-style), build the `claude -p` args,
   run serially, capture stdout→`summary.log` + the JSON `session_id`, update the store, re-upload `summary.md`,
   post `.summaryDidFinish`; graceful when `claude` is missing. TDD the testable seams (prompt assembly, arg
   construction, resource loading, the claude-availability check). **Gate:** `swift test`.
5. **DriveSync / DriveAuth** — add `summary.md`; `.md` MIME in the re-upload. **Gate:** `swift test` / build.
6. **JobBridge trigger** — kick `SummaryRunner` after `driveBackup` when `autoSummary` is on + `claude` is
   present; non-blocking, best-effort. **Gate:** `swift build`.
7. **UI** — `MeetingDetailView` Summary panel (running / done / failed / not-run + Copy / Retry / Summarize);
   Settings ▸ Recording "Auto-summarize finished calls" toggle. **Gate:** `make gen` + `make build-mac`.
8. **Verify** — build green + app launches; write the manual-test checklist (the live `claude -p` run is
   Yuval's manual test).

## Risks / watch-outs
- **`claude` on PATH in a GUI-launched app** (no inherited shell env) — mirror `JobBridge`'s explicit `PATH`
  and add `~/.local/bin` (where `claude` installs) alongside `/opt/homebrew/bin`. Graceful failure + a
  settings hint if absent.
- **`.md` resource bundling** — verify XcodeGen copies the whole `skills/` tree into the `.app` (it copies
  non-source files found under a source path; confirm in the built bundle).
- **The headless run itself** (recipe correctness + the `acceptEdits` write) is **live-verify only** — not
  unit-testable.
