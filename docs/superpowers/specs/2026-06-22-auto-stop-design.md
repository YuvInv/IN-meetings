# Auto-stop on meeting end — design (2026-06-22)

**Status:** approved direction (Yuval, 2026-06-22). **Scope:** detect that a recorded call has ended and
offer a **visible, cancelable countdown auto-stop** — never a silent stop. P1 v1 must-have.
**Amends ADR-002** (stop logic) and **the 2026-06-14 auto-stop decision** (which had chosen
"keep recording if ignored"; the new behavior is "visible countdown → auto-stop unless cancelled").

## Goal

When a live call the app is recording ends, stop the recording (and run the normal
transcribe → package → Drive → summary pipeline) **without the user having to babysit it** — while
**never silently dropping or cutting a meeting**. The user always sees a countdown and can cancel with one
click.

## Decisions (settled)

- **Trigger = the detector's `armed → idle` edge** (Core Audio bidirectional I/O stops = the call app's
  audio process exited). This is the symmetric counterpart of the `idle → armed` edge the start-prompt
  already uses. No new detection mechanism. *(This is the roadmap's "research how other recorders detect
  meeting-end" answered: call-app audio-process exit is the chosen signal; call-window-close and
  calendar-end-time are **out of v1** — the audio signal is sufficient and already proven on the start side.)*
- **Visible countdown → auto-stop, cancelable** (Yuval 2026-06-22). The card shows
  "Meeting ended — stopping in {n}s…"; if not cancelled it auto-stops + processes. **Not silent** — the
  countdown is visible and one click keeps recording. This **supersedes** the 2026-06-14 "keep recording if
  ignored" choice.
- **Debounced** so a network blip / brief reconnect doesn't false-fire: the call must stay idle for the
  full debounce window before the countdown even appears.
- **Edge-triggered, re-offers on a fresh call-end** (Yuval 2026-06-22). "Keep recording" cancels the
  *current* countdown; a later genuine `armed → idle` edge (rejoin then leave again) re-offers.
- **Never silent guarantee:** a stop only ever happens through the visible countdown card. If auto-stop is
  disabled in Settings, there is no auto-stop at all (manual stop only). If the card cannot be presented for
  any reason, default to **keep recording** — never stop blind.
- **Defaults (tunable):** debounce **12 s**, countdown **30 s**, tick cadence **1 s**. Settings toggle
  `autoStopEnabled` default **on**; **Settings-only** (no menu-bar quick toggle in v1).

## The flow

```
detector armed → idle edge, while RecordingController.isRecording
  → debounce 12 s
       ├─ re-arms before 12 s  → cancel (network blip)
       └─ still idle at 12 s    → show MeetingEndOverlay card, start countdown 30 s
            ├─ re-arms during countdown      → cancel card, keep recording
            ├─ user clicks "Keep recording"  → cancel card, keep recording
            ├─ recording stopped elsewhere   → reset to inactive, hide card
            └─ countdown hits 0  OR  "Stop now"  → recorder.stop()  [normal pipeline]
```

`recorder.stop()` is synchronous and already kicks the full transcribe → package → Drive → summary chain —
nothing new downstream. The package/summary path is unchanged.

## Components

### 1. `AutoStopArbiter` (Core, NEW, unit-tested)

A **pure, tick-driven state machine** — no clock, no UI, no timers. Mirrors how `CallDetector` keeps the
testable logic in Core. Driven one tick (nominally 1 s) at a time so every timing path is deterministic in
tests (the project bans `Date.now()` in tests).

```
enum State { case inactive
             case debouncing(ticksLeft: Int)
             case countingDown(ticksLeft: Int) }

enum Action { case none
              case showCountdown(remaining: Int)   // seconds to display
              case stopNow
              case hide }

struct AutoStopArbiter {
    var debounceTicks: Int = 12
    var countdownTicks: Int = 30
    private var state: State = .inactive
    private var wasArmed: Bool = false   // to detect the armed→idle edge

    // Called once per tick with the current world.
    mutating func tick(status: DetectionState.Status,
                       isRecording: Bool,
                       enabled: Bool) -> Action
}
```

Behavior in `tick`:
- If `!enabled` or `!isRecording` → reset to `.inactive`, return `.hide` (if a card was up) else `.none`.
- Detect the **`armed → idle` edge** via `wasArmed`. On that edge while inactive → `.debouncing(debounceTicks)`.
- `.debouncing`: if `status == .armed` → cancel to `.inactive`. Else decrement; at 0 → `.countingDown(countdownTicks)`, return `.showCountdown(countdownTicks)`.
- `.countingDown`: if `status == .armed` → cancel to `.inactive`, return `.hide`. Else decrement; if >0 return `.showCountdown(remaining)`; at 0 → `.inactive`, return `.stopNow`.
- External cancel (Keep recording) and external stop are explicit methods (`keepRecording()`,
  `recordingStopped()`) that reset to `.inactive`.

`wasArmed` is set to `status == .armed` at the end of every tick, so the `armed → idle` edge is detected
exactly once (and becomes `false` once idle). `keepRecording()` only resets `state` to `.inactive`; because
we are already idle, no new edge fires until the status goes back to `.armed` and then `.idle` again — i.e. a
genuine new call-end re-offers.

### 2. `MeetingDetectionSettings` (Core, extend)

Add `autoStopEnabled: Bool` (default **on**, key `meetingPrompt.autoStopEnabled`), persisted in
`UserDefaults`, following the exact pattern of `promptEnabled`. This is the symmetric home of the
start-prompt prefs.

### 3. `MeetingEndCoordinator` (app, NEW)

Mirrors `MeetingPromptCoordinator`. Owns:
- a 1 s `Timer` that, each tick, calls `arbiter.tick(status: detector.state.status,
  isRecording: recorder.isRecording, enabled: settings.autoStopEnabled)` and acts on the `Action`;
- a floating **non-activating `NSPanel`** (same panel config as the start card — borderless, `.statusBar`
  level, `canJoinAllSpaces`/`fullScreenAuxiliary`, clear background) hosting the overlay;
- the actions: `.showCountdown(n)` → present/refresh the card with `n`; `.hide` → fade out;
  `.stopNow` → `recorder.stop()` then hide.

Card button wiring: **Stop now** → `arbiter.recordingStopped()` + `recorder.stop()` + hide;
**Keep recording** → `arbiter.keepRecording()` + hide.

### 4. `MeetingEndOverlay` (app, NEW SwiftUI)

Liquid Glass card mirroring `MeetingPromptOverlay`'s visual language. Copy:
**"Meeting ended"** / **"Stopping in {n}s…"**, buttons **[Stop now]** (primary) and **[Keep recording]**.
Takes the live `remaining` seconds (coordinator pushes it each tick) plus `onStopNow` / `onKeepRecording`
closures. A `#if DEBUG` preview hook (like the start card) to render it without a real call.

### 5. Wiring — `INMeetingsApp.swift`

Construct a `MeetingEndCoordinator(detector:recorder:settings:)` alongside the existing
`MeetingPromptCoordinator` (reuse the same `detector`, `recorder`, and `MeetingDetectionSettings`
instances) and call `.start()`. Add the `autoStopEnabled` toggle to the Settings → Recording tab next to
the existing start-prompt toggle.

## Scope & guarantees

- **Only while actively recording.** No recording → the arbiter never leaves `.inactive`. By construction the
  `armed → idle` edge means a call was active, so this targets call recordings (the typical `.call` profile).
- **Never silent.** A stop happens only via the visible countdown. Disabled → no auto-stop. Card can't
  present → keep recording.
- **Resets cleanly** if the recording is stopped by any other means (menu Stop, app quit) mid-debounce or
  mid-countdown.

## Error handling / edge cases

- **Network blip / brief reconnect:** the 12 s debounce absorbs it (idle must persist the full window).
- **Mute-all / screen-share-only segments:** the call app keeps its audio I/O streams open while in the
  call, so `armed` holds; no false end. (The probe arms on bidirectional I/O, not on live speech.)
- **Recording started before a call, call then ends:** still offers (a call did end). Acceptable.
- **App launched mid-call, then call ends:** the coordinator seeds `wasArmed` from the first observed
  status; the first real `armed → idle` after that fires normally.
- **Rapid leave/rejoin:** debounce cancels on re-arm; only a sustained idle reaches the countdown.

## Out of scope (v1)

- Calendar-end-time and call-window-close as triggers (audio signal is sufficient; revisit only if the
  audio edge proves noisy on a real call).
- A menu-bar quick toggle for auto-stop (Settings toggle only).
- Auto-stop for non-call / mic-only manual recordings with no detected call (no edge to trigger on).
- Confirmed-silence gating of the countdown (the VAD-hybrid option Yuval did **not** pick).

## Testing

`Tests/INMeetingsCoreTests/AutoStopArbiterTests.swift` (deterministic, tick-driven):
- debounce cancels on re-arm before the window elapses;
- countdown appears only after the **full** debounce;
- `showCountdown` remaining decrements each tick;
- re-arm during countdown → `.hide`, resets;
- `keepRecording()` during countdown → resets; a later fresh `armed → idle` edge re-offers;
- countdown reaching 0 → `.stopNow` exactly once;
- `enabled == false` → never fires;
- `isRecording == false` → never fires;
- `recordingStopped()` mid-flow → resets to `.inactive`.

Coordinator + card = **manual GUI test on a real call** (the verification gate): record a call → leave →
confirm the countdown card appears after ~12 s, counts down, **Keep recording** cancels it, and letting it
run to 0 auto-stops + processes → Drive + summary. Checklist to be added under
`docs/manual-tests-auto-stop.md` during implementation.

## Files

- `Sources/INMeetingsCore/Detection/AutoStopArbiter.swift` — NEW (Core, tested)
- `Sources/INMeetingsCore/Detection/MeetingDetectionSettings.swift` — add `autoStopEnabled`
- `Tests/INMeetingsCoreTests/AutoStopArbiterTests.swift` — NEW
- `Apps/INMeetings/INMeetings/MeetingEndCoordinator.swift` — NEW (app)
- `Apps/INMeetings/INMeetings/MeetingEndOverlay.swift` — NEW (app, SwiftUI)
- `Apps/INMeetings/INMeetings/INMeetingsApp.swift` — construct + start the coordinator; Settings toggle
- New app-target files require `make gen` before `make build-mac`; Core files are auto-picked by SPM.

## ADR / docs impact

- **Amends ADR-002** (capture pipeline / stop logic): adds the debounced visible-countdown auto-stop.
- **Supersedes the 2026-06-14 auto-stop sub-decision** ("keep recording if ignored").
- DECISIONS.md gets a 2026-06-22 entry; HANDOFF.md + IMPLEMENTATION_PLAN.md item 10 flip to "in progress".
