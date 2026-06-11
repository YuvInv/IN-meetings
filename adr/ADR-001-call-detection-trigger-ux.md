# ADR-001 — Call detection & trigger UX

**Status:** Proposed (revised after P3 prototype) · **Date:** 2026-06-11 · **Deciders:** Yuval (review)
**Brief item:** A · **Research:** RESEARCH.md §1, §4 · **Empirical:** P3 (`prototypes/p3-detect`)

> **P3 UPDATE — verified live (M4/macOS 26).** The primary detection signal is **Core Audio per-process
> audio I/O**, not app/tab heuristics. A process with **both input *and* output audio running** is a
> live call; the process's bundle ID names the app. This is how real call-recorders do it: app-agnostic
> (Zoom/Meet/WhatsApp/Teams uniformly), needs **no Automation/Accessibility/Screen-Recording
> permission**, doesn't depend on the app being frontmost, and cleanly rejects one-way playback
> (YouTube = output-only). Verified: YouTube → `armed=no`; Google Meet w/ mic → `armed=YES CALL in:
> Google Chrome`. The earlier frontmost-app + AppleScript-tab-URL plan was prototyped and **failed**
> (missed a backgrounded Meet call; needed Automation) — it is demoted to optional enrichment.

## Context

The recorder must notice a meeting started, reliably, while invisible to other participants, across
Zoom (native), Google Meet (browser), Teams, Slack huddles, and generic calls — then offer to record
without stealing focus from a fullscreen meeting. Key facts:

- **Core Audio exposes per-process audio I/O** (`kAudioHardwarePropertyProcessObjectList` →
  `kAudioProcessPropertyBundleID` / `…IsRunningInput` / `…IsRunningOutput`, macOS 14.2+). Reading it
  needs **no special permission**. This is the reliable, app-agnostic call signal.
- `kAudioDevicePropertyDeviceIsRunningSomewhere` (device-level mic-in-use) returns false for Bluetooth
  mics (AirPods) — so device-level mic is unreliable; the **per-process** input flag is what we use.
- Browser-tab-URL via AppleScript needs Automation TCC and depends on frontmost — too fragile to be a
  primary signal (P3 proved this).

## Decision

**Primary detection = Core Audio bidirectional process I/O + prompt-to-record + a non-activating panel.**

**Detection signals (in priority order):**
1. **Bidirectional process audio (PRIMARY)** — enumerate audio processes; a process with **input AND
   output running** is a live call. Identify the app from `kAudioProcessPropertyBundleID` (normalize
   helper IDs, e.g. `com.google.Chrome.helper` → Chrome). No permission required. ✅ verified in P3.
2. **Calendar (enrichment)** — an event with a video link live now confirms/names the meeting and
   supplies company/attendees for context (ADR-004); also lets us arm slightly *before* audio starts.
3. **Native meeting app running** (`NSWorkspace`) — a weak corroborating hint / friendly-name source.
4. *(Optional, only if ever needed)* browser tab URL via AppleScript — NOT required; the audio signal
   already covers browser calls. Keep out of the default path (avoids the Automation permission).

**Edge case (known):** a call with the **mic muted from the start** is output-only and looks like
playback. Mitigate by latching "in a call" once bidirectional has been seen, and by using calendar
context; full mute-from-start detection is a minor follow-up, not a blocker.

**Arming policy (debounced):** arm when **a bidirectional-audio process is present** (held ~2 s to
ignore blips) **OR a calendar meeting with a link is live now**. One-way playback never arms (verified).

**Trigger UX — prompt, don't auto-record.** Default is a one-click prompt, because (i) confidential
internal/HR calls must not be silently captured (ADR-010), and (ii) even MacWhisper ships auto-record
as beta with data-loss warnings. To remove the "I clicked too late" failure, run a **rolling
ring-buffer** of the system+mic tap (last ~90 s, in memory/scratch) the moment detection arms; if the
user confirms, the buffer is prepended so nothing is lost. Per-user opt-in "auto-record meetings that
match a calendar event" is available but **off by default**.

**The banner** — borderless **non-activating `NSPanel`**:
- `styleMask: [.nonactivatingPanel, .hudWindow]`, `isFloatingPanel = true`, `hidesOnDeactivate = false`
- `level = .floating` (or `.statusBar`-adjacent), `collectionBehavior = [.canJoinAllSpaces,
  .fullScreenAuxiliary]` → stays visible over fullscreen Zoom/Meet without taking focus.
- `NSWindow.sharingType = .none` so the banner never appears in a screen share (verify on Tahoe).
- Content: company/meeting name (from calendar), Record / Pause / "Don't record this", a quiet
  recording dot. Minimal, draggable, auto-positions top-center.

**Menu-bar agent:** `LSUIElement = true` (no Dock icon), launch-at-login via `SMAppService`. The
menu-bar item is the home for status, the dashboard, recent meetings, and settings.

## Options considered

| Option | Why not |
|--------|---------|
| Device-level mic-in-use (`…DeviceIsRunningSomewhere`) | AirPods blind spot (returns false); can't identify the app. Superseded by per-process input flag. |
| Frontmost-app + AppleScript tab-URL | **Prototyped in P3 and failed** — missed a backgrounded Meet call, needs Automation TCC, per-browser fragility. Demoted to optional enrichment. |
| Browser extension for tab detection | Per-browser installs + moving parts; unnecessary now that the audio-process signal covers browser calls. |
| Auto-record everything | Confidentiality risk (internal/HR), legal exposure (ADR-010), false triggers. |
| Notification Center prompt | Invisible/awkward over fullscreen meetings; a floating panel is reliably visible. |

## Consequences

- **Good:** robust and **app-agnostic** (one mechanism for Zoom/Meet/WhatsApp/Teams); **no Automation,
  Accessibility, or Screen-Recording permission** for detection; frontmost-independent; rejects one-way
  playback; identifies the app for free. No missed pre-roll (ring-buffer); never steals focus; prompt
  default respects confidentiality. **All verified live in P3.**
- **Costs/risks:** a mic-muted-from-start call is output-only (looks like playback) — mitigate via
  latch + calendar (minor follow-up). The per-process audio API is macOS 14.2+ (fine — floor is 26).
  The "no Screen-Recording-permission" *capture* path still depends on ADR-002's tap choice (P2).
- **P3 verified** the detection mechanism. **P2** still needs runtime verification (tap permission +
  fullscreen banner).
