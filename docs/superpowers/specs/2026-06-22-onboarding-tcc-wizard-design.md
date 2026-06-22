# Onboarding / TCC permission wizard — design (2026-06-22)

**Status:** approved direction (Yuval, 2026-06-22). **Scope:** a first-run stepped wizard that walks a
non-technical teammate through the grants the app needs, with plain-language explanations and graceful
fallbacks. P0 — the adoption gate. (ADR-009.)

## Goal

Installing IN Meetings shouldn't mean a wall of scary, unexplained system prompts. A first-launch wizard
explains *why* each permission is needed, triggers each prompt in order, shows live status, and degrades
gracefully when a grant is skipped or denied — so a ~5-person VC team can self-install.

## Decisions (settled)

- **Four grants, in order:** Microphone → System Audio Recording → Screen Recording → Google sign-in.
- **Screen Recording is included in first-run, with a restart at the end** (Yuval 2026-06-22). Its grant
  only takes effect on a relaunch, so the **Done** step offers a **"Restart IN Meetings"** button — the one
  relaunch is front-loaded so the first recorded call already has video.
- **Every step is skippable; nothing blocks the dashboard.** The app degrades (no mic → manual-only; no
  system audio → one-sided; no screen recording → audio-only; no Google → no Drive/Calendar). Mic is
  *encouraged*, not forced.
- **Re-runnable:** a "Re-run setup…" button in Settings + a dashboard **"Finish setup"** nudge whenever a
  grant is still missing.
- **The `claude`-CLI check (auto-summary) is a non-blocking info row on the Done step**, not a full step.
- **Out of scope (v1):** per-browser Automation / Apple-Events grants (we detect calls via Core Audio, not
  tab URLs — not needed) and EventKit (calendar rides the Google OAuth, already covered).

## The grants — mechanics (why each step differs)

| Grant | Check | Prompt | Wrinkle |
|---|---|---|---|
| Microphone | `AVCaptureDevice.authorizationStatus(.audio)` | `Permissions.requestMicrophone()` (async) | clean — checkable + promptable |
| System Audio Recording | **none** | fires only when a process **tap is created** | provoke via a short-lived throwaway tap; denial only shows later as a silent system track |
| Screen Recording | `Permissions.hasScreenRecording()` (`CGPreflight…`) | `Permissions.requestScreenRecording()` | **grant takes effect only after a relaunch** |
| Google (Drive + Calendar) | `DriveAuth.status` | `DriveAuth.connect()` (one OAuth, both scopes) | network; shows the connected email |

## Flow (stepped Liquid Glass window, opens on first launch)

1. **Welcome** — one line on what the app does + "~1 minute."
2. **Microphone** — explain "to record your side of the call." Button → `requestMicrophone()`; status pill
   (granted ✓ / denied → "Open Settings"). Skip allowed.
3. **System Audio Recording** — explain "to hear the other side of calls." Button → provoke the prompt via
   `Permissions.provokeSystemAudioPrompt()` (a short-lived tap). No reliable status read, so the step is
   marked *attempted* and offers "Open System Settings" as the fallback / fix-it path.
4. **Screen Recording** — explain "to record the call window (video)." `hasScreenRecording()` for status;
   button → `requestScreenRecording()`; note "takes effect after a restart." Skip allowed (video off until
   granted).
5. **Google sign-in** — explain "to back up recordings to Drive and read your calendar for context." Button →
   `drive.connect()`; shows the connected email. Optional inline "Choose backup folder…" (reuses the existing
   Drive picker), skippable.
6. **Done** — a recap checklist (each grant ✓ / skipped) + a non-blocking info row for the `claude` CLI
   (detected / not found → link to install). If Screen Recording was just granted (needs a relaunch), the
   primary button is **"Restart IN Meetings"**; otherwise **"Finish"**. Either way, sets
   `onboarding.completed`.

## Architecture

Mirrors the project's Core-logic / app-UI split (e.g. `AutoStopArbiter` + `MeetingEndCoordinator`).

### `OnboardingChecklist` (Core, NEW, unit-tested)
Pure value type. Given a `PermissionsSnapshot(micGranted:screenGranted:googleConnected:)`, computes the
outstanding steps and an `isComplete`-enough predicate. Drives both the wizard recap and the dashboard
"Finish setup" nudge — one source of truth, testable without TCC.

```
struct PermissionsSnapshot { let micGranted, screenGranted, googleConnected: Bool }
struct OnboardingChecklist {
    static func outstanding(_ s: PermissionsSnapshot) -> [Step]   // e.g. [.microphone, .google]
    static func isSetUp(_ s: PermissionsSnapshot) -> Bool          // mic + google as the "usable" floor
}
enum Step { case microphone, systemAudio, screenRecording, google }
```
(System Audio has no readable status, so it is *not* part of the `isSetUp` floor — only mic + Google gate the
"usable" state; screen recording is "nice to have" for video.)

### `Permissions.provokeSystemAudioPrompt()` (Core, NEW)
Creates a short-lived process tap purely to fire the System-Audio TCC prompt, then tears it down. **Technical
risk:** a tap may not be creatable without a live call target. If provocation proves unreliable, the System-
Audio step degrades to the **instructional fallback** (open System Settings ▸ Privacy ▸ Screen & System Audio
Recording, toggle IN Meetings on) — confirmed during implementation; the step ships either way.

### `OnboardingModel` (app, NEW, @Observable)
Owns the current step, the live actions (wraps `Permissions` + `DriveAuth`), and persists
`onboarding.completed` in `UserDefaults`. Permission probes/requesters are **injectable** so step-advance and
completion logic are unit-testable (the `MeetingDetectionSettings` test pattern). Exposes `restartApp()`
(re-launch via `NSWorkspace` + `terminate`) for the Done step.

### `OnboardingWindow` + `OnboardingStepView` (app, NEW SwiftUI)
A `Window` scene (id `onboarding`), Liquid Glass, with a reusable step chrome (icon, title, explanation,
primary action, status pill, Skip/Back/Next). `OnboardingWindow` switches on `model.step`.

### Wiring — `INMeetingsApp.swift`
- Add the `OnboardingModel` + a `Window("Setup", id: "onboarding")` scene.
- At launch (in `AppDelegate.applicationDidFinishLaunching`), if `!onboarding.completed`, open the
  onboarding window and front it (`NSApp.activate`); it sits in front of the dashboard until completed. The
  dashboard is not suppressed (the app stays usable), just behind.
- Settings → a "Re-run setup…" button (opens the onboarding window).
- Dashboard → a dismissible "Finish setup" banner when `OnboardingChecklist.isSetUp` is false.

## Error handling / degradation
- **Denied mic:** step shows "Open Settings"; app still reaches the dashboard (manual recording only).
- **Denied / skipped system audio:** recordings are one-sided; the existing `systemCapturedSilence` flag and
  the `lastError` surface already nudge the user post-hoc.
- **Screen Recording granted but not yet live:** Done step's "Restart" makes it effective; if the user skips
  the restart, video stays off until they next relaunch (existing behavior).
- **Google connect fails (network):** `DriveAuth.status == .failed(msg)` shown inline with a Retry; skippable.
- **Re-running** after partial setup: the wizard reflects current status (granted steps show ✓), so it's safe
  to run repeatedly.

## Testing
- `OnboardingChecklistTests` (Core): `outstanding`/`isSetUp` across the permission-combination matrix.
- `OnboardingModelTests` (app/Core): step advance, skip, and `onboarding.completed` persistence with injected
  probes (no real TCC).
- Live TCC prompts + the relaunch = **manual GUI test** (`docs/manual-tests-onboarding.md`): fresh-user
  first-run walks all four prompts; deny-then-fix; skip-everything still reaches the dashboard; re-run setup;
  the dashboard "Finish setup" nudge.

## Files
- `Sources/INMeetingsCore/Onboarding/OnboardingChecklist.swift` — NEW (Core, tested)
- `Sources/INMeetingsCore/Capture/Permissions.swift` — add `provokeSystemAudioPrompt()`
- `Tests/INMeetingsCoreTests/OnboardingChecklistTests.swift` — NEW
- `Apps/INMeetings/INMeetings/Onboarding/OnboardingModel.swift` — NEW (app)
- `Apps/INMeetings/INMeetings/Onboarding/OnboardingWindow.swift` — NEW (app, SwiftUI)
- `Apps/INMeetings/INMeetings/Onboarding/OnboardingStepView.swift` — NEW (app, reusable chrome)
- `Apps/INMeetings/INMeetings/INMeetingsApp.swift` — onboarding window scene + first-run open + Settings
  "Re-run setup" + dashboard nudge wiring
- New app-target files need `make gen`; Core files are auto-picked by SPM.

## ADR / docs impact
- Implements the **ADR-009** onboarding-wizard item (minus the out-of-scope Automation/EventKit grants).
- DECISIONS.md gets a 2026-06-22 entry; IMPLEMENTATION_PLAN.md P0 item 3 flips to in-progress/done.
