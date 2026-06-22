# Manual tests — onboarding / TCC wizard

`OnboardingChecklist` (outstanding / isSetUp) is unit-tested. What needs eyes: the wizard UI, the live TCC
prompts, first-run auto-open, and the Screen-Recording relaunch.

## First-run open
1. Reset the flag so it behaves like a fresh install:
   `defaults delete com.in-venture.INMeetings onboarding.completed` (adjust bundle id if different), then
   launch the debug build.
2. **Expect:** the "Set up IN Meetings" window floats centered, in front of the dashboard. Progress dots at
   the top; **Welcome** screen with the app icon + "Get started".

## Walk the steps
3. **Get started** → **Microphone:** click **Allow Microphone** → macOS mic prompt → status pill flips to
   **Granted ✓**. **Continue**.
4. **System Audio:** click **Show the prompt** → macOS "System Audio Recording" prompt appears (this is the
   throwaway-tap provocation). Note the fallback line about System Settings. **Continue**.
5. **Screen Recording:** click **Allow Screen Recording** → macOS prompt + adds IN Meetings to the list. Pill
   may stay "not yet" (takes effect on restart) and the note says so. **Continue**.
6. **Google:** click **Connect Google…** → browser OAuth → returns; shows **Connected as <email>** + the
   "pick a backup folder in Settings" note. **Continue**.
7. **Done:** recap list shows ✓ / — per grant; Screen Recording shows "· after restart" (orange); the Claude
   CLI row shows detected/optional. Because Screen Recording is pending, the primary button is **Restart IN
   Meetings**.

## Restart path
8. Click **Restart IN Meetings** → the app relaunches. After relaunch, open **Set up IN Meetings…** from the
   menu → Screen Recording now shows **Granted ✓** and the Done button is **Finish**.

## Skip / never-blocks
9. Fresh run again; on each step click **Continue without granting**. **Expect:** you still reach **Done** and
   **Finish** closes the wizard — nothing blocks the dashboard.

## Re-run + nudge
10. Menu bar → **Set up IN Meetings…** reopens the wizard from Welcome at any time, reflecting current grants
    (already-granted steps show ✓).
