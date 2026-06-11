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

## P3 — meeting detection ([ADR-001](../adr/ADR-001-call-detection-trigger-ux.md)) — ✅ VERIFIED

**Mechanism (the one real call-recorders use):** enumerate Core Audio processes
(`kAudioHardwarePropertyProcessObjectList`); a process with **both input AND output audio running** is
a live call, and its `kAudioProcessPropertyBundleID` names the app. App-agnostic, frontmost-independent,
**no Automation / Accessibility / Screen-Recording permission**, and it rejects one-way playback.

```bash
cd prototypes/p3-detect
swift run p3-detect            # prints armed=YES/no every 2s; Ctrl-C to stop
```

**Verified live (M4 / macOS 26.5):**
- ✅ YouTube playback → `armed=no` (Chrome output-only — correctly not a call).
- ✅ Google Meet with mic on → `armed=YES  CALL in: Google Chrome` (bidirectional), even backgrounded.
- ✅ Call ended → back to `armed=no`. No permission prompt at any point.

Still worth a pass when convenient:
- [ ] Confirm the same for **Zoom** (native), **Teams**, **Slack huddle**, **WhatsApp**.
- [ ] **AirPods:** confirm detection still works (per-process input flag, unlike device-level mic-in-use).
- [ ] Note the mic-muted-from-start edge case (output-only → looks like playback; latch + calendar mitigate).

---

## Build all
```bash
( cd prototypes/p2-capture && swift build )
( cd prototypes/p3-detect  && swift build )
```
Captured `*.wav` and `.build/` are gitignored.
