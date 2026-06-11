# ADR-001 — Call detection & trigger UX

**Status:** Proposed · **Date:** 2026-06-11 · **Deciders:** Yuval (review)
**Brief item:** A · **Research:** RESEARCH.md §1, §4

## Context

The recorder must notice a meeting started, reliably, while invisible to other participants, across
Zoom (native), Google Meet (browser), Teams, Slack huddles, and generic calls — then offer to record
without stealing focus from a fullscreen meeting. Two hard facts from research constrain this:

- `kAudioDevicePropertyDeviceIsRunningSomewhere` (mic-in-use) **always returns false for Bluetooth
  mics (AirPods)** — Apple-acknowledged, unresolved. Mic-in-use alone misses AirPods users.
- There is **no public API to learn which app holds the mic**, and browser meetings need the active
  tab URL to recognize Meet — readable via AppleScript (Automation TCC), not reliably via AX.

## Decision

**Multi-signal detection + prompt-to-record + a non-activating floating panel.**

**Detection (fuse signals; never rely on mic-in-use alone):**
1. **Running meeting app** — `NSWorkspace` frontmost/running bundle IDs (`us.zoom.xos`, `Microsoft
   Teams`, `com.tinyspeck.slackmacgap`, browsers).
2. **Mic-in-use rising edge** — `…DeviceIsRunningSomewhere` on the default input (works for built-in/
   wired; treated as a strong *positive*, never a required signal because of AirPods).
3. **Browser tab URL** — for browsers, AppleScript `URL of active tab of front window` → match
   `meet.google.com`, `teams.microsoft.com`, `*.zoom.us/j/`, etc. (Automation TCC, not Accessibility).
4. **Calendar** — an event with a video link active now (±the event window) both arms detection early
   and supplies the company/attendees for context (ADR-004).

**Arming policy (debounced):** arm when **(a meeting app is frontmost/running AND (mic-in-use OR a
meeting URL is active)) OR (a calendar meeting with a link is live now)**. Require the condition to
hold ~2 s before showing the banner; ignore short blips (notification sounds, Voice Memos, music — a
music app frontmost is never a meeting). This is the disambiguation the brief asks for.

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
| Mic-in-use only (Granola-style core) | AirPods blind spot → missed recordings for the most common VC setup. |
| Auto-record everything | Confidentiality risk (internal/HR), legal exposure (ADR-010), and false triggers. |
| Browser extension for tab detection | More moving parts + per-browser installs; AppleScript covers Safari/Chrome with one Automation grant. Keep an extension as a later option only if AppleScript proves insufficient for Meet. |
| Notification Center prompt | Invisible/awkward over fullscreen meetings; a floating panel is reliably visible. |

## Consequences

- **Good:** robust across platforms; no missed pre-roll (ring-buffer); never steals focus; respects
  confidentiality by defaulting to prompt.
- **Costs/risks:** Automation TCC per browser in onboarding; Firefox has no AppleScript tab access
  (degrade to app+mic detection there); the "no screen-recording-permission" path depends on ADR-002's
  tap choice. The ring-buffer must be discarded securely if the user declines (ADR-010).
- **Prototype 3** de-risks Meet/browser detection and AirPods behavior; **Prototype 2** de-risks the
  banner over fullscreen.
