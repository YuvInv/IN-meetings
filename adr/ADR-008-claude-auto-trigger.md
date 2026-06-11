# ADR-008 — Claude auto-trigger & skill chaining

**Status:** Proposed · **Date:** 2026-06-11 · **Deciders:** Yuval (review)
**Brief item:** F (auto-trigger) · **Depends on:** ADR-005 (package), ADR-001 (meeting type)

## Context

The payoff: on meeting completion, run the Claude skills against the package so the partner gets a
Saventa summary (and optionally a MoM and founder enrichment) without five manual steps. Claude Code
runs headless via `claude -p`. The skills now accept a local package (ADR-005).

## Decision

**A headless `claude -p` chain, configurable per meeting, defaulting to one-click (not silent auto).**

**Trigger modes (per meeting; default = one-click):**
- **One-click (default):** when the package is ready, the dashboard/banner shows "Summarize in Claude";
  one click runs the chain. Default because output should get a human glance before it lands in the CRM,
  and because not every meeting should be processed (internal/HR).
- **Auto:** opt-in per meeting or per rule — fires the chain automatically on completion. Suitable for
  external founder pitches matched to a calendar event.

**The chain (composition, not a monolith):**
```
package ready
   └─► saventa-summary  --package <path>      (always, when triggered)  → short note → write back
        └─► generate-mom --package <path>      (optional)               → MoM .docx  → write back
             └─► process-meeting --package …   (optional)               → CRM upload (human-review gate kept)
        └─► enrich-company  <company>          (optional)               → Dealigence enrichment of new people
```
Each step writes its output back into the package folder and re-syncs to Drive (ADR-006). `process-meeting`
keeps its existing human-review-before-upload gate — we don't auto-write the CRM blindly.

**Meeting-type routing (the cheap, high-value steal from Circleback — RESEARCH §2/§6):** a small rule
set decides which steps run, keyed on signals already in `metadata.json`:
- external founder pitch (external attendees, calendar-matched, new/early deal) → summary + (optional) MoM + enrich.
- existing portfolio/deal check-in → summary only.
- internal / 1-on-1 / HR (all-internal attendees) → **nothing** (and likely not recorded at all — ADR-010).
Rules are user-editable; default conservative (summary only) when unsure.

**Execution mechanics:** the Python pipeline shells out to `claude -p "<skill invocation>"` with the
package path, capturing stdout/exit code, surfacing status in the dashboard, and storing results +
run metadata in SQLite. Failures are non-fatal to the package (the folder + transcript still exist);
the dashboard offers retry. Concurrency limited (one chain at a time) to keep it observable.

## Options considered

| Option | Why not |
|--------|---------|
| Always auto-run everything | Confidential/internal meetings shouldn't be auto-summarized or pushed to CRM; output deserves a human glance. Default to one-click; auto is opt-in. |
| Wire skills via an SDK/library call instead of `claude -p` | `claude -p` is the supported headless surface and matches how the user already runs skills; no need to re-host them. |
| One mega-prompt that does summary+MoM+CRM+enrich | Loses composability and per-meeting choice; harder to debug; the skills are deliberately separate. |
| Auto-push to CRM without review | `process-meeting` intentionally has a human-review gate; keep it. |

## Consequences

- **Good:** one trigger instead of five manual steps; reuses the user's existing skills unchanged
  except for the `--package` input; routing avoids wasting runs (and avoids processing sensitive
  calls); results flow back to Drive automatically.
- **Costs/risks:** depends on `claude -p` being available in the environment the app runs in (document
  in onboarding; handle "claude not found" gracefully). Headless skill runs can be long — surface
  progress, don't block the UI. Quota/cost is per the user's Claude plan; one-click default keeps it
  in the user's control. The routing rules need sensible defaults so they don't mis-route a sensitive
  call into the CRM.
