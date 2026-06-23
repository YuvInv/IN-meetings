# Modular / resizable meeting layout — design BRIEF (2026-06-22)

**Status:** captured requirements (Yuval, 2026-06-22). **NOT yet designed** — brief for the next session to
brainstorm into a spec. Sequenced **after** the calendar-upload feature ("then…").

## Vision (Yuval's words, paraphrased)
In a meeting's detail view, the elements — the **video pane**, the **summary**, and the **transcript** —
should be **modular and resizable**. The user should be able to resize the different elements.

## Current state
`MeetingDetailView` is a **fixed vertical `VStack`**: video player (top, when present) → summary panel →
transcript area (fills remaining space). Sizes are fixed; nothing is draggable or collapsible. For
audio-only meetings the video pane is absent.

## Key open questions / decisions for next session
1. **How "modular"?** Three escalating scopes — confirm which:
   - **(a) Resizable** — draggable dividers between panes (simplest, likely the ask).
   - **(b) + Collapsible** — hide/show the summary or video pane.
   - **(c) + Rearrangeable** — move panes around (most work; probably out of v1).
2. **Layout arrangement** — keep the vertical stack with draggable dividers (`VSplitView`), or go
   **side-by-side** (e.g. video|transcript via `HSplitView`, summary as a collapsible region)? Must **adapt
   when there's no video** (audio-only meetings) so the layout doesn't leave a dead pane.
3. **Persistence** — remember the user's sizes (and collapsed state) across launches via `SceneStorage` /
   `UserDefaults`. Global (same for every meeting) or per-meeting? (Lean: global.)
4. **Liquid Glass** — dividers/handles + pane chrome styled consistently with the macOS-26 Liquid Glass UI.

## Existing building blocks
- SwiftUI **`HSplitView` / `VSplitView`** (AppKit-backed `NSSplitView`, draggable dividers) — the natural fit;
  or a custom drag-divider for finer Liquid-Glass control.
- `MeetingDetailView` (the view to refactor), `TranscriptSegmentView`, the summary panel, the `AVPlayerView`
  wrapper (AppKit — note the earlier SwiftUI `VideoPlayer` crash, fixed by wrapping AppKit `AVPlayerView`).
- `SceneStorage`/`UserDefaults` for persisted sizes.

## Rough approach sketch (to be validated, not final)
Replace the fixed `VStack` with split containers (likely `VSplitView`, or `HSplitView` for video|transcript),
make the summary a resizable/collapsible region, persist divider positions, and branch the layout when the
meeting has no video. Keep the existing AppKit `AVPlayerView` wrapper for the video pane.

## Out of scope (first cut, unless decided otherwise)
- Fully rearrangeable / drag-and-drop pane reordering.
- Pop-out windows for individual panes.
