# Modular / resizable meeting layout — design (2026-06-23)

**Status:** approved by Yuval 2026-06-23. Supersedes the requirements brief
`2026-06-22-modular-meeting-layout-brief.md`. Next: implementation plan via `writing-plans`.

## Goal
Make a meeting's detail view **modular and resizable**: the user can resize the video, summary, and
transcript panes, and hide the summary pane. Today `MeetingDetailView` is a fixed top-to-bottom `VStack`
(header → summary → video → speaker chips → transcript → audio bar) with hardcoded heights and nothing
draggable.

## Decisions (locked)
- **Arrangement: side-by-side** — a left **context column** (video + summary) and a right **transcript
  column**, split by a draggable divider. Transcript gets full height next to the media instead of being
  pushed below it. Adapts when there is no video (audio-only → Summary | Transcript) and when there is no
  context at all (transcript fills full width — no dead pane).
- **Collapse: the summary pane** can be hidden/shown via a header toggle (not the video or transcript).
- **Persistence: global** — divider fractions and the summary-visible flag are the same for every meeting,
  stored in `@AppStorage` (the app's existing persistence idiom, e.g. `showCalendarPanel`).
- **Splitter: a custom `ResizableSplit`**, not SwiftUI `HSplitView`/`VSplitView` (rationale below).

## Layout

```
┌──────────────── header (full width) ─────────────────┐  header + a "Summary" show/hide toggle
├───────────────────────────────────────────────────────┤
│  CONTEXT COLUMN        ⇆   TRANSCRIPT COLUMN           │  outer horizontal ResizableSplit
│  ┌─ video ──────┐          speaker chips               │
│  │              │          ┌─ transcript (RTL) ─────┐  │
│  ├──── ⇅ ───────┤          │                        │  │  inner vertical ResizableSplit
│  │ summary      │          │                        │  │  (video / summary)
│  └──────────────┘          └────────────────────────┘  │
├───────────────────────────────────────────────────────┤
│  audio playback bar (full width — audio-only meetings) │
└───────────────────────────────────────────────────────┘
```

### Transcript column (right — always present, primary)
- Speaker chips (`speakerLegend`) move here, to the top of the column (they describe the transcript's
  speakers).
- The RTL transcript scroll (`transcriptArea`) fills the rest.
- Failure / "no transcript yet" states keep their existing `ContentUnavailableView`s, shown in this column.

### Context column (left — conditional)
Holds the media + summary. Its contents depend on what exists:

| isVideo | summary shown* | context column |
|---------|----------------|----------------|
| yes     | yes            | inner vertical split `{ video / summary }` |
| yes     | no             | video only |
| no      | yes            | summary only |
| no      | no             | **omitted** → transcript fills full width |

\* "summary shown" = `showSummaryPane` is on **and** the summary panel has something to render for this
meeting (running / done / failed / a "Summarize" affordance for a transcribed meeting). When the summary
panel would render nothing, it does not count as content.

### Audio playback bar (footer)
- Shown only for **audio-only** meetings (no video), full width at the bottom — unchanged trigger from
  today (`!isVideo && player != nil`).
- Video meetings use the `AVPlayerView` inline transport controls, so there is no footer for them.

## Collapse — summary show/hide
- A **"Summary" button in the detail header** (alongside Copy / Reveal), backed by
  `@AppStorage("showSummaryPane")`, default **on**.
- Reuses the toggle idiom the app already uses for the Calendar inspector (`showCalendarPanel` in
  `DashboardWindow`).
- Hiding the summary reflows the layout: a video meeting becomes video | transcript; an audio meeting
  becomes transcript full-width (the context column disappears — no near-empty column). Video and
  transcript are always visible.
- Default-on means the "Summarize" CTA / progress spinner stays discoverable; only a user who wants
  maximum transcript space turns it off.

## Components (designed for isolation)
1. **`SplitLayout` (Core, pure) — `Sources/INMeetingsCore/Dashboard/SplitLayout.swift`**
   Pure clamp math: given a total length, the two panes' minimum lengths, and a requested divider fraction,
   return a legal fraction (and/or the resolved first-pane length). This is the only logic worth unit-testing
   and it lives in Core so it gets coverage. No SwiftUI.
2. **`ResizableSplit` (app target, Liquid Glass) — `Apps/INMeetings/INMeetings/Dashboard/ResizableSplit.swift`**
   One reusable two-pane splitter:
   - `axis: .horizontal | .vertical`, two `@ViewBuilder` panes.
   - A thin Liquid-Glass drag handle; `onHover` cursor (`.resizeLeftRight` / `.resizeUpDown`).
   - Min sizes per side; uses `SplitLayout` to clamp during drag and on container resize.
   - Persists its divider fraction itself via an injected `@AppStorage` key.
   - Chrome stays LTR (the divider math is not RTL-mirrored); only the transcript *content* is RTL, scoped
     inside the transcript pane exactly as today.
3. **`MeetingDetailView` refactor — `Apps/INMeetings/INMeetings/Dashboard/MeetingDetailView.swift`**
   Recompose the body from the fixed `VStack` into: `header` → `body` (the splitter tree, computed from the
   isVideo / summary-shown matrix above) → optional audio footer. The existing sub-views (`header`,
   `summaryPanel`, `speakerLegend`, `transcriptArea`, `playbackBar`, `PlayerView`) are **relocated, not
   rewritten** — `summaryPanel` drops its internal `maxHeight: 220` cap (the pane is now user-sized).

## Persistence keys (`@AppStorage`, global)
- `detail.columnSplit` (Double) — context-column width fraction of the body.
- `detail.mediaSplit` (Double) — video height fraction within the context column.
- `showSummaryPane` (Bool, default true) — summary visibility.

Defaults: column ≈ 0.38 (context) / 0.62 (transcript); media ≈ 0.55 (video) / 0.45 (summary). Min sizes:
context column ≈ 240pt, transcript ≈ 320pt, video ≈ 120pt, summary ≈ 80pt. Fractions are clamped to legal
values for the current container size on every drag and resize, so a shrunk window never produces an
illegal split.

## Alternatives considered
- **SwiftUI `HSplitView` / `VSplitView`** (rejected as primary): native dividers, but no built-in
  cross-launch persistence of divider position and limited handle styling — both are first-class
  requirements here. A small custom splitter gives persistence + glass + min-size clamping in one focused,
  reusable file.
- **`NSSplitView` autosave via `NSViewRepresentable`** (rejected): would give free divider persistence, but
  hosting SwiftUI panes inside an AppKit split view (per-pane `NSHostingView`) is awkward and harder to keep
  glass-consistent than a ~one-file SwiftUI splitter.
- **Per-meeting persisted sizes** (rejected): more state for no clear benefit; the brief leans global and a
  single remembered layout matches user expectation for a detail view.
- **Rearrangeable / drag-and-drop pane reordering, pop-out windows** (out of scope — brief).

## Interactions / edge cases
- **Nested inside `NavigationSplitView` + `.inspector`**: the detail already lives inside the dashboard's
  sidebar|detail split with an optional Calendar inspector. The new inner columns nest fine; min sizes keep
  it usable even with sidebar + inspector + both inner columns open (desktop, wide windows at our scale).
- **No transcript yet (processing/failed)**: transcript column shows the existing unavailable/failed view;
  the context column can still show video (e.g. a video import) or the summary affordance.
- **Summary toggled off mid-session**: layout reflows immediately; persisted on next launch.
- **Window narrower than the sum of mins**: `SplitLayout` clamps to the largest legal split; panes respect
  their mins (acceptable minor overflow only on an unrealistically narrow window).

## Testing
- **Core unit tests** for `SplitLayout` clamping (normal split, fraction below/above legal range, total
  smaller than the sum of mins, degenerate zero/near-zero totals).
- **`make build-mac` green**, `swift build` + Core suite green.
- **Live run (acceptance — build-green is not acceptance for UI):** open a **video** meeting and an
  **audio-only** meeting; drag the column divider and the video/summary divider; toggle Summary off/on
  (verify audio meeting collapses to full-width transcript, video meeting to video|transcript); **relaunch**
  and confirm the divider sizes and summary visibility persisted; confirm the Hebrew transcript still reads
  RTL inside its pane.

## Out of scope
- Rearrangeable / drag-and-drop pane reordering; pop-out windows for individual panes (brief).
- Any change to the transcript, summary, or playback *behavior* — this is a layout refactor only.
