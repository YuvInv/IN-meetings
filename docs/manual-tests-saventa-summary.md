# Manual tests — saventa-summary auto-trigger

Branch `feat/saventa-summary-autotrigger`. Run these on the built app (`make run-mac`). The headless
`claude -p` core was already verified end-to-end against the golden fixture (writes a correctly-formatted
`summary.md`, exit 0, parseable session id); these cover the **UI + the live record→summary→Drive flow**,
which need the running app. Prereq: `claude` installed + signed in (it is — `~/.local/bin/claude`).

## A. Golden path — auto-summary on a finished call
1. Record (or finish) a **call** with audio. When the pipeline finishes, the meeting opens in the dashboard.
2. The **Summary** panel (top of the detail) shows **"Generating summary…"** (spinner), then within a
   ~minute flips to the **paste-ready Saventa note** (monospace, literal `**Team**` / `**Funding **` etc.).
   → **Copy** copies it to the clipboard; pasting into Saventa keeps the asterisks.
3. `summary.md` exists in the meeting folder, and (if Drive is connected) appears in the meeting's Drive
   folder alongside the package.

## B. Manual trigger + states
4. Open a **transcribed** meeting that has no summary → the panel shows **"No summary yet."** + a
   **Summarize** button. Tap it → spinner → note. (Works for in-person meetings too — auto only fires for calls.)
5. On a done summary, **Re-summarize** regenerates it cleanly (overwrites).

## C. Settings + graceful failure
6. Settings ▸ Recording → **"Auto-summarize finished calls"** toggle (default **on**). Turn **off** → a newly
   finished call does **not** auto-summarize (panel stays "No summary yet."); the manual **Summarize** button
   still works.
7. **`claude` missing/logged out** (simulate: rename `~/.local/bin/claude` or sign out) → tap Summarize →
   panel shows **failed** with a clear hint + a **Retry** button. The transcript/recording are unaffected.
   (Restore `claude`, Retry → succeeds.)

## Watch-outs
- First summary after a fresh login may be slower (model warm-up).
- The summary is **transcript-only** by design — empty sections (e.g. Market) mean it wasn't discussed on
  the call; that's correct, not a bug.
- CRM posting is **out of scope** — the summary lands in the app + Drive only.
