# Custom summaries — in-app recipe editor + multiple summaries per meeting

**Date:** 2026-06-25 · **Branch:** `feat/v1-breadth-features` · **Status:** approved (Yuval)

## Problem

A2 made summary recipes selectable, but two gaps make it unusable in practice:
1. **Creating a custom recipe means dropping a `recipe.md` in a folder** — bad UX. Users should create/edit
   summary instructions in the Settings tab and have the app save them.
2. **A meeting holds exactly one summary** (`summary.md`, overwritten on each run). Running a second recipe
   clobbers the first. Users want **several summaries per meeting** (e.g. a Saventa deal summary *and* a
   short bullet brief) that coexist and are viewable, plus a way to **choose which recipe to run per meeting**.

## Design

### Part 1 — In-app recipe editor (Settings → Summary)
A custom recipe = **a name + free-text instructions** (written from scratch; no "start from", no house-style).
- Stored by the app at `~/Library/Application Support/IN Meetings/Recipes/<slug>/`: `recipe.md` (instructions)
  + `name.txt` (the user's exact display name, preserving casing/acronyms).
- Settings → Summary replaces the "Reveal custom recipes folder" button with a **Custom recipes** list
  (Edit / Delete per row; bundled recipes shown read-only) and a **＋ New recipe** action that opens a
  **sheet**: Name field + a large Instructions `TextEditor` + Save / Cancel.
- Saving creates/updates the recipe; it appears in the active-recipe picker immediately.

**Core:** new `SummaryRecipeStore` — `create(name:instructions:)`, `update(id:name:instructions:)`,
`delete(id:)`, `instructions(id:)`, `displayName(id:)`; pure file I/O under an injected `userRoot`
(unit-tested with a temp dir). `slug(from:)` (lowercase, spaces→`-`, strip non-alphanumerics, ensure unique
vs existing folders). Edit keeps the recipe **id stable** (only `name.txt` + `recipe.md` change) so an active
selection never breaks. `SummaryRecipeRegistry` reads `name.txt` for the display name when present (bundled
recipes unchanged — still humanized from the folder id).

### Part 2 — Multiple summaries per meeting + per-meeting recipe choice

**Files.** Each recipe's output is its own file: `summaries/<recipeId>.md` in the meeting folder. `summary.md`
is kept as a **mirror of the most-recently-completed** summary (back-compat for downstream Claude skills).
Legacy meetings (only `summary.md`, no `summaries/`) are surfaced as a single `saventa-summary` entry.

**State.** New SQLite table (**migration v5**) `meetingSummary(meetingId, recipeId, state, error, sessionId,
updatedAt, PRIMARY KEY(meetingId, recipeId))` tracking per-(meeting, recipe) `running|done|failed`. MeetingStore
gains `upsertSummary(...)`, `summaries(forMeeting:) -> [MeetingSummary]`, `deleteSummary(meetingId:recipeId:)`.
The existing `meeting.summaryState`/`summaryError` columns are kept and updated as a **rollup** (latest run's
state) so the dashboard meeting-list indicator and the pre-Part-3 detail view keep working.

**SummaryRunner.** `run(meetingID:folder:recipeOverride:)` resolves the recipe (active if nil), writes
`summaries/<recipeId>.md` (the `makeArguments` prompt now names that path; the runner creates `summaries/`
first), updates the per-recipe row + the rollup, copies the result to `summary.md` (mirror), and syncs the
per-recipe file to Drive. The in-flight guard becomes **per-(meeting, recipe)** so different recipes can run
without dropping each other; the same recipe twice is still guarded. Output contract: still Markdown; the
frozen `transcript.json`/`metadata.json` schemas are untouched.

**JobBridge / RecordingStore.** `summarize(meetingID:folder:recipeID:)` already threads a recipe id — route it
to `run(recipeOverride:)`. Auto-summary on call-finish runs the **active** recipe (unchanged behavior).
RecordingStore exposes, for a meeting: the list of its summaries (recipeId + displayName + state) and the text
of a given one (`summaryText(for:recipeId:)`), plus delete.

**Meeting page (MeetingDetailView).**
- **"Summarize ▾"** — the run action becomes a menu of recipes; picking one runs it for this meeting (the
  per-meeting recipe choice). Shown both as the empty-state CTA and as a ＋ within the pane.
- **Summary pane switcher** — a dropdown at the top of the pane listing every summary that exists for this
  meeting (each tagged done / running / failed). Selecting one shows its content; **＋ Summarize with…** adds
  another. Each shown summary has **Copy**, **Re-run** (re-runs that recipe), and **Delete**.
- The earlier per-meeting `showSummaryPane` (shown-by-default) behavior is unchanged.

**Drive.** Each `summaries/<recipeId>.md` syncs alongside the package (reuses the existing summary-sync hook,
generalized to a path/recipe).

## Build order (subagent-driven, each: tests + `swift build`/`make build-mac` + review)
1. **T1 — Recipe editor:** `SummaryRecipeStore` + registry `name.txt` + `SummarySettingsTab` list + editor sheet.
2. **T2 — Multi-summary backend:** migration v5 table + MeetingStore methods + `SummaryRunner` per-recipe files
   & mirror & per-recipe guard + `JobBridge`/Drive + legacy read. Keeps the rollup + `summary.md` mirror so the
   existing detail/list UI stays functional until T3.
3. **T3 — Multi-summary UI:** `MeetingDetailView` switcher + Summarize ▾ menu + per-summary Copy/Re-run/Delete;
   `RecordingStore` per-recipe accessors.

## Out of scope / unchanged
House-style/example editing for custom recipes; "start from existing"; voice-ID; the frozen package JSON schemas;
`SummaryRunner`'s `claude -p` flags beyond the output path.

## Verification (live, Yuval)
Create a custom recipe in Settings → it appears in the picker; on a meeting, **Summarize ▾** → run two
different recipes → both appear in the pane switcher, switchable, neither overwrites the other; Copy/Re-run/Delete
work; auto-summary on a real call still produces the active recipe's summary; both summary files land on Drive.
