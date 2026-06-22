# Manual tests — auto-stop on meeting end

The `AutoStopArbiter` timing logic is fully covered by `AutoStopArbiterTests` (deterministic, tick-driven).
What automated tests can't see is the **card rendering + the live armed→idle→countdown→stop flow on a real
call**. Run these by eye before declaring the feature done.

## Quick visual check (no real call needed)
1. Launch the debug build → menu bar → **"Preview meeting-ended countdown (debug)"**.
2. **Expect:** the Liquid Glass card floats top-right: title **"Meeting ended"**, **"Stopping in 30s…"**
   counting down each second, a thin bar draining left, buttons **[Stop now]** / **[Keep recording]**.
3. Click **Keep recording** (or **Stop now**) → the card fades out. (Preview buttons only dismiss — no real
   recorder side effects.)

## Golden path (real call)
1. Start a Google Meet / Zoom call → accept the **"Record now"** card (or start recording manually).
2. Confirm recording is running (menu bar shows recording).
3. **Leave / end the call.**
4. **Expect:** after ~12 s of the call being gone (debounce), the **"Meeting ended — stopping in 30s…"**
   card appears and counts down.
5. Let it run to 0 → recording **auto-stops** and the normal pipeline runs (transcribe → package → Drive →
   summary). Confirm the meeting shows up in the dashboard.

## Cancel paths
6. Repeat 1–4, then click **Keep recording** before 0 → card disappears, **recording continues** (check the
   menu bar still shows recording). Stop manually when done.
7. Repeat 1–4, then click **Stop now** → stops immediately + processes (same as the menu Stop).

## Debounce / blip (best-effort)
8. During a call, briefly drop Wi-Fi (or mute/leave-and-rejoin within a few seconds). **Expect:** no card —
   the 12 s debounce rides out the blip and recording keeps going.

## Settings
9. Menu bar → toggle **"Offer to stop when the call ends"** OFF. Repeat 1–4. **Expect:** no countdown card,
   recording keeps going until you stop it manually (never silent). Toggle back ON.

## Re-offer
10. Repeat 1–4, **Keep recording**, then rejoin the call and leave again. **Expect:** the countdown
    re-appears on the fresh call-end.
