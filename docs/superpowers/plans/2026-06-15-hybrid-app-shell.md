# Hybrid App Shell (Dock app + menu-bar tray) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make IN Meetings BOTH a real Mac app (persistent Dock icon that opens the dashboard) AND a menu-bar tray for quick *Record-now*, where closing the dashboard never quits the recorder and clicking the Dock icon re-opens the dashboard.

**Architecture:** Flip the app target from `LSUIElement=true` (pure menu-bar agent, no Dock icon) to a regular Dock-visible app, keep the existing `MenuBarExtra` and `Window(id:"dashboard")` SwiftUI scenes, and add a small `NSApplicationDelegate` (via `@NSApplicationDelegateAdaptor`) for the AppKit lifecycle callbacks SwiftUI doesn't expose: keep-alive on last-window-closed, and reopen-on-Dock-click. A tiny `DashboardLauncher` singleton bridges those AppKit callbacks to SwiftUI's `openWindow(id:)` action (captured by the always-present menu-bar label view). This **amends ADR-001/ADR-009** (recorded in `DECISIONS.md`, 2026-06-15).

**Tech Stack:** Swift, SwiftUI (`App`/`Scene`/`MenuBarExtra`/`Window`), AppKit (`NSApplicationDelegate`), XcodeGen + `make build-mac`/`make run-mac`. Deployment target macOS 26.0.

---

## Verification philosophy (read first)

This change is **app lifecycle + Info.plist**, which has no honest unit-test seam — there is no pure logic to assert, and the app target has no test bundle (tests live in the `INMeetingsCore` SPM package only). Per the project's standards, **"BUILD SUCCEEDED" is not verification for app/UI code** — every task is verified by **building AND running the app and observing the documented behavior**. Each task below ends with a concrete run-and-observe step with explicit expected results. Do not mark a task done on a clean compile alone.

No new app-target *files* are introduced (all new types live in the existing `INMeetingsApp.swift`), so **`make gen` is not required** — `make build-mac` suffices.

## File structure

- **Modify** `Apps/INMeetings/INMeetings/Info.plist:25-26` — `LSUIElement` `true` → `false` (Dock-visible app).
- **Modify** `Apps/INMeetings/INMeetings/INMeetingsApp.swift` — add `@NSApplicationDelegateAdaptor`; add `DashboardLauncher`, `AppDelegate`, and a `MenuBarLabel` view (all in this file — it is the app entry/lifecycle file, so lifecycle glue belongs here and we avoid `make gen`); swap the inline `MenuBarExtra` label for `MenuBarLabel`; refresh the now-stale "Open Dashboard" comment.

No changes to `project.yml`, the entitlements, the Python pipeline, or `INMeetingsCore`.

---

## Task 0: Branch + land the roadmap docs

**Files:** none (git only). The working tree currently has the uncommitted v1-roadmap doc edits (IMPLEMENTATION_PLAN.md, DECISIONS.md, HANDOFF.md) on the stale, already-merged `feat/app-ux-dashboard` branch.

- [ ] **Step 1: Branch off the synced `main`**

```bash
git fetch origin
git switch main && git pull --ff-only
git switch -c feat/hybrid-app-shell
```

(The uncommitted doc edits follow you onto the new branch — `git switch` keeps working-tree changes.)

- [ ] **Step 2: Commit the roadmap docs as their own commit**

```bash
git add IMPLEMENTATION_PLAN.md DECISIONS.md HANDOFF.md docs/superpowers/plans/2026-06-15-hybrid-app-shell.md
git commit -m "docs: prioritized road to a team-ready v1 + hybrid app-shell decision + P0 #1 plan"
```

---

## Task 1: Make it a Dock-visible app (Info.plist)

**Files:**
- Modify: `Apps/INMeetings/INMeetings/Info.plist:25-26`

- [ ] **Step 1: Flip `LSUIElement` to `false`**

Change:

```xml
	<key>LSUIElement</key>
	<true/>
```

to:

```xml
	<key>LSUIElement</key>
	<false/>
```

- [ ] **Step 2: Build**

Run: `make build-mac`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Run and observe (Dock icon + tray coexist)**

Run: `make run-mac`
Expected, all true at once:
- A **Dock icon** for "IN Meetings" appears (it did not before).
- The app appears in the **Cmd-Tab** application switcher.
- The **menu-bar tray icon** (waveform) is **still present**, and clicking it still shows the menu (Open Dashboard / Start Recording / Drive / Quit).

(The dashboard may or may not auto-open at this point — Task 2 makes launch + Dock-click deterministic. Quit the app before the next task: tray menu → "Quit IN Meetings".)

- [ ] **Step 4: Commit**

```bash
git add Apps/INMeetings/INMeetings/Info.plist
git commit -m "feat(app): show a Dock icon (LSUIElement=false) — hybrid Dock + menu-bar shell"
```

---

## Task 2: Lifecycle glue — keep-alive, reopen-on-Dock-click, open-on-launch

**Files:**
- Modify: `Apps/INMeetings/INMeetings/INMeetingsApp.swift`

- [ ] **Step 1: Add the delegate adaptor to the `App` struct**

In `struct INMeetingsApp: App`, add the adaptor as the first stored property (immediately under `struct INMeetingsApp: App {`, before `@State private var detector`):

```swift
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
```

- [ ] **Step 2: Swap the inline menu-bar label for a `MenuBarLabel` view**

Replace the `MenuBarExtra` `label:` closure (currently the `if recorder.isRecording { Text(...) } else { Image(...) }` block, INMeetingsApp.swift:47-54) so the whole `MenuBarExtra` reads:

```swift
        MenuBarExtra {
            MenuContent(detector: detector, recorder: recorder, models: models,
                        settings: promptSettings, coordinator: promptCoordinator, drive: drive)
        } label: {
            MenuBarLabel(detector: detector, recorder: recorder)
        }
        .menuBarExtraStyle(.menu)
```

- [ ] **Step 3: Refresh the stale "Open Dashboard" comment**

In `MenuContent.body`, the "Open Dashboard" button comment (INMeetingsApp.swift:79) currently says it is an `LSUIElement` app. Change that one line from:

```swift
            NSApp.activate(ignoringOtherApps: true)   // LSUIElement menu-bar app: bring the window forward
```

to:

```swift
            NSApp.activate(ignoringOtherApps: true)   // hybrid Dock + menu-bar app: bring the dashboard forward
```

- [ ] **Step 4: Add `DashboardLauncher`, `AppDelegate`, and `MenuBarLabel` at the end of the file**

Append to `INMeetingsApp.swift` (after the closing `}` of `MenuContent`):

```swift
/// Bridges AppKit lifecycle callbacks (Dock-icon clicks, last-window-closed) to SwiftUI's `openWindow`
/// action, which `NSApplicationDelegate` cannot reach (it has no SwiftUI environment). The closure is
/// installed by `MenuBarLabel` — the one SwiftUI view that is always present (the menu-bar status item).
@MainActor
final class DashboardLauncher {
    static let shared = DashboardLauncher()
    /// Set once by `MenuBarLabel.onAppear`; calls `openWindow(id: "dashboard")`.
    var open: (() -> Void)?
    private init() {}
}

/// Hybrid Dock + menu-bar lifecycle. The app is a regular, Dock-visible app (`LSUIElement=false`) that
/// also lives in the menu bar: closing the dashboard must NOT quit the recorder, and clicking the Dock
/// icon (re)opens the dashboard. Amends ADR-001/ADR-009 (was a pure `LSUIElement` menu-bar agent).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keep the recorder + menu-bar item alive when the dashboard window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Dock-icon click with no visible window → bring the app forward and (re)open the dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.activate(ignoringOtherApps: true)
            DashboardLauncher.shared.open?()
        }
        return true
    }

    /// Open the dashboard on launch so it feels like a real app. (P0 #2 / launch-at-login will gate this
    /// so a *login-item* start stays quiet in the background instead of popping the window.)
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { DashboardLauncher.shared.open?() }
    }
}

/// The menu-bar status item: draws the icon/timer AND installs the `DashboardLauncher` closure. It is the
/// only always-present SwiftUI view in this app, so its environment is where we capture `openWindow`.
private struct MenuBarLabel: View {
    var detector: CallDetector
    var recorder: RecordingController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if recorder.isRecording {
                Text("🔴 \(recorder.elapsedString)")
                    .monospacedDigit()
            } else {
                Image(systemName: detector.state.status == .armed ? "waveform.badge.mic" : "waveform")
            }
        }
        .onAppear {
            DashboardLauncher.shared.open = { openWindow(id: "dashboard") }
        }
    }
}
```

- [ ] **Step 5: Build**

Run: `make build-mac`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Run and observe (the three lifecycle behaviors)**

Run: `make run-mac`
Expected, in order:
1. **On launch**, the dashboard window opens (real-app feel), Dock icon + menu-bar icon both present.
2. **Close the dashboard** with the red traffic-light button → the **app keeps running**: the menu-bar icon is still there and the menu still opens; the Dock icon is still present. (It must NOT quit.)
3. With the dashboard closed, **click the Dock icon** → the dashboard **re-opens** and comes to the front.
4. Open the menu-bar tray → **Start Recording** still records (short 5–10 s clip), then **Stop**; the pipeline phase text appears. (Tray quick-record still works.)

If behavior 1 does not occur (window does not auto-open on launch) but 3 works, the launcher closure was not yet installed when `applicationDidFinishLaunching` fired; the dashboard is still reachable via Dock-click and the menu. Acceptable, but prefer behavior 1 — if it is flaky, set the dashboard `Window` scene modifier `.defaultLaunchBehavior(.presented)` (macOS 15+) instead of opening from `applicationDidFinishLaunching`, and re-run.

- [ ] **Step 7: Commit**

```bash
git add Apps/INMeetings/INMeetings/INMeetingsApp.swift
git commit -m "feat(app): hybrid shell lifecycle — keep recorder alive on dashboard close + reopen on Dock click"
```

---

## Task 3: Integrated regression pass

**Files:** none (verification only).

The shell change touches app activation, which can ripple into the detection overlay and the Drive sign-in sheet (the `ASWebAuthenticationSession` anchor in `DriveAuth.swift:122-127` previously assumed *no* main window). Confirm nothing regressed.

- [ ] **Step 1: Run the app**

Run: `make run-mac`

- [ ] **Step 2: Walk the manual checklist**

Confirm each, on a real run:
1. **Dock + tray** both present; Cmd-Tab lists the app. ✅ from Task 1.
2. **Dashboard:** opens on launch; browse a past meeting, play its `audio.m4a`, transcript renders RTL. (Regression — dashboard intact.)
3. **Close → keep-alive → Dock-click reopen** all behave (Task 2 behaviors 2–3).
4. **Quick record from tray:** Start → short clip → Stop → pipeline runs → the meeting appears in the dashboard. (Core flow intact.)
5. **Drive menu:** "Connect Google Drive…" presents the sign-in sheet without crashing (the auth anchor now usually has a real window); if already connected, the "Choose backup location" menu still lists Shared Drives. (Regression risk from the `LSUIElement` flip.)
6. **"Record now" overlay:** trigger a detected call (or the DEBUG "Preview record prompt") → the Liquid Glass card floats and stays above other windows. (Regression — `MeetingPromptCoordinator`.)
7. **Quit:** menu-bar "Quit IN Meetings" (and ⌘Q while the dashboard is focused) terminates the app cleanly.

- [ ] **Step 3: If all green, the feature is done**

No code change in this task. If any item fails, fix it before closing the task (e.g., Drive anchor: prefer the key window — `NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()` — in `DriveAuth.authAnchor`).

---

## Self-Review

**1. Spec coverage** — the P0 #1 spec (DECISIONS 2026-06-15 "hybrid Dock + menu-bar app shell" + IMPLEMENTATION_PLAN "Road to a team-ready v1" item 1):
- Persistent Dock icon → Task 1 (`LSUIElement=false`). ✅
- Keep the menu-bar tray (`MenuBarExtra`) → unchanged scene + verified Task 1 Step 3. ✅
- Don't quit when the dashboard closes (`terminateAfterLastWindowClosed=false`) → Task 2 `AppDelegate`. ✅
- Dock-click (re)opens the dashboard (`applicationShouldHandleReopen`) → Task 2. ✅
- Quiet launch-at-login → **explicitly deferred to P0 #2** (launch-at-login/SMAppService isn't built yet); noted in `applicationDidFinishLaunching` and the roadmap. Not a gap — a scoped boundary. ✅

**2. Placeholder scan** — no TBD/TODO; every code step shows the full code; the only conditional ("if launch auto-open is flaky, use `.defaultLaunchBehavior(.presented)`") is a concrete, named fallback, not a placeholder. ✅

**3. Type consistency** — `DashboardLauncher.shared.open` (optional closure) is defined in Task 2 Step 4 and called in the same type's `AppDelegate` methods and set in `MenuBarLabel.onAppear`; window id `"dashboard"` matches the existing `Window(... id: "dashboard")` (INMeetingsApp.swift:57); `MenuBarLabel(detector:recorder:)` init params match the call site in Step 2. ✅

---

## Notes for the executor

- **Verification is manual-run, by design** (lifecycle/Info.plist change; no unit-test seam, no app-target test bundle). A clean `make build-mac` is necessary but **not** sufficient — you must `make run-mac` and observe.
- **No `make gen`** needed (no new files).
- Keep `NSApp.activate(ignoringOtherApps: true)` to match the existing call site style (the app already uses it at INMeetingsApp.swift:79).
- This is P0 #1 of the "Road to a team-ready v1" roadmap; P0 #2 (Developer-ID sign + notarize + `.dmg` + launch-at-login) will add the quiet-login gate to `applicationDidFinishLaunching`.
