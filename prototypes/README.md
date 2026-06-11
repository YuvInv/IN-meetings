# Phase-0 prototypes — P2 (capture) & P3 (detection)

Two SwiftPM command-line prototypes that de-risk the capture and detection unknowns from
[IMPLEMENTATION_PLAN.md](../IMPLEMENTATION_PLAN.md). **Both compile clean** (`swift build`); runtime
verification needs you at the machine (TCC permission grants + a live meeting), as agreed.

> Status: built & compile-checked by Claude. **Runtime verification: pending (Yuval).**
> Record results in the checklists below.

---

## P2 — dual-track capture ([ADR-002](../adr/ADR-002-capture-pipeline.md))

Captures **two separate tracks** with no virtual driver: system/remote audio via a **Core Audio process
tap**, mic via **AVAudioEngine**. Proves the no-Screen-Recording-permission capture path.

```bash
cd prototypes/p2-capture
swift run p2-capture 15        # capture 15 seconds
```
While it runs: **play a YouTube video** (→ system.wav) and **talk into the mic** (→ mic.wav).
First run prompts for **Microphone** and **System Audio Recording** permission (the embedded Info.plist
supplies the prompt text).

**Verify (the de-risking questions):**
- [ ] Capture works after granting only **Microphone** + **"System Audio Recording Only"** — **no
      Screen Recording prompt** appeared. ⬅ the key claim
- [ ] `system.wav` contains the played audio; `mic.wav` contains your voice — **two clean tracks**.
- [ ] (Over days) **no monthly "Allow For One Month" re-approval nag** for this audio-only app.
- [ ] Try with **AirPods** as mic + built-in speakers (aggregate-device edge case).
- [ ] Echo check: on speakers (no headphones), does mic.wav pick up the remote audio? (→ offline AEC needed.)

_Note:_ a plain `swift run` binary is unsigned; if macOS blocks the tap, grant the binary under
System Settings ▸ Privacy & Security ▸ System Audio Recording, or wrap it in a signed `.app` (the real
app will be Developer-ID signed — [ADR-009](../adr/ADR-009-app-architecture-ipc.md)).

---

## P3 — meeting detection ([ADR-001](../adr/ADR-001-call-detection-trigger-ux.md))

Multi-signal detector: running/frontmost apps (NSWorkspace) + mic-in-use (CoreAudio) + active browser
tab URL (AppleScript). Prints an `armed=YES/no` verdict every 2 s.

```bash
cd prototypes/p3-detect
swift run p3-detect            # Ctrl-C to stop
```
First time a browser is frontmost, it prompts for **Automation** permission (to read the tab URL).

**Verify:**
- [ ] Open **Zoom** (native) → `armed=YES`, `meetingApps=[Zoom]`.
- [ ] Open **Google Meet** in Chrome/Safari → `armed=YES`, `urlHit=true (meet.google.com)`.
- [ ] Open **Teams** / **Slack huddle** → detected.
- [ ] **AirPods test:** join a call on AirPods → confirm `mic=false` (the Apple bug) but `armed=YES`
      still (because app/URL signals carry it). ⬅ proves multi-signal is necessary.
- [ ] No false `armed=YES` from a music app or notification sound.
- [ ] Automation permission (not Accessibility) is sufficient for tab URLs.

---

## Build all
```bash
( cd prototypes/p2-capture && swift build )
( cd prototypes/p3-detect  && swift build )
```
Captured `*.wav` and `.build/` are gitignored.
