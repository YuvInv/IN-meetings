# Manual tests — onboarding / TCC wizard

`OnboardingChecklist` (outstanding / isSetUp) is unit-tested. What needs eyes: the wizard UI, the live TCC
prompts, first-run auto-open, and the Screen-Recording relaunch. **3 grant steps** (macOS 15/26 folds system
audio into "Screen & System Audio Recording", so there's no separate system-audio step).

> ⚠️ **To actually see the prompts you need a clean TCC state.** macOS remembers grants by bundle id and they
> can carry into a new user account. Before a fresh test, in the test session (app quit):
> `tccutil reset All com.in-venture.in-meetings`, then relaunch. Otherwise an already-granted permission
> simply won't prompt (correct behavior, but not a test of the first-grant path).

## First-run open
1. Reset the first-run flag: `defaults delete com.in-venture.in-meetings onboarding.completed`, then launch.
2. **Expect:** the "Set up IN Meetings" window floats centered, in front of the dashboard. Progress dots
   (5: Welcome + 3 grants + Done); **Welcome** screen with the app icon, "Get started", and a model-download
   line ("Model: downloading NN%… (runs in the background)" → "On-device Hebrew model ready.").

## Walk the steps
3. **Get started** → **Microphone:** click **Allow Microphone** → macOS mic prompt → pill flips to
   **Granted ✓**; the footer button becomes a prominent **Continue**. (Before granting, the footer is a quiet
   **Skip for now** — the only prominent button is "Allow Microphone", so they don't compete.)
4. **Screen & System Audio Recording:** click **Allow Screen & System Audio** → macOS prompt + adds IN Meetings
   to the **Screen Recording** list. Pill may stay "Not yet" (takes effect on restart) with a note saying so.
   A **"Open Screen Recording settings…"** link is there if the prompt is missed. **Continue/Skip**.
5. **Google:** click **Connect Google…** → browser OAuth → **Connected as <email>** + "pick a backup folder in
   Settings". **Continue**.
6. **Done:** recap shows Microphone / Screen & System Audio Recording / Google / on-device model / Claude CLI.
   Screen row shows "· after restart" (orange) when pending. Primary button is **Restart IN Meetings** when a
   Screen-Recording grant is pending, else **Finish**.

## Restart path
7. Click **Restart IN Meetings** → app relaunches. Re-open **Set up IN Meetings…** → Screen & System Audio now
   shows **Granted ✓**, Done button is **Finish**.

## Confirms the merged grant (the macOS-26 finding)
8. With only **Screen & System Audio Recording** granted (no separate system-audio toggle exists), record a
   short call → the **"Them" / system track has audio** (not silent). One grant covers window video + the
   other side's audio.

## Skip / never-blocks
9. Fresh run; click **Skip for now** on every grant. **Expect:** you still reach **Done**; **Finish** closes
   the wizard — nothing blocks the dashboard.

## Model management (Settings → Models)
10. Settings → **Models**: each model shows **Installed ✓ + size**, the **storage path**, **Reveal in Finder**,
    and an **⋯ menu** with Reveal / Re-download / Delete. Delete → row flips to downloading; Re-download works.

## Re-run + nudge
11. Menu bar → **Set up IN Meetings…** reopens the wizard from Welcome anytime, reflecting current grants
    (already-granted steps show ✓; status re-checks when you return from System Settings).
