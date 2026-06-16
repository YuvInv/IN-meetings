# Manual test script — reliability + call video + Drive folder picker

Branch `feat/reliability-video-drive-picker` (commits `56642b0`, `2ba876e`, `880f8cf`). Automated checks
already pass (**Core 76 tests, pipeline 54, `make build-mac`, app launches**). These steps cover the
**live behaviour** only a human can confirm. Each step: *do → expect*.

Meeting files live in `~/Library/Application Support/IN Meetings/Recordings/<timestamp>/`
(`mic.wav` · `system.wav` · `video.mov` · `meeting.mp4` / `audio.m4a` · `metadata.json` · `pipeline.log`).
Models live in `~/Library/Application Support/IN Meetings/Models/`.

## 0. Prerequisites (once)

1. Build + run: `make run-mac` (or `make build-mac` then launch the `.app`).
2. Grant **Microphone** + **System Audio Recording** when first prompted, then **relaunch** (TCC grants
   need a relaunch to take effect).
3. For video (§B): System Settings ▸ Privacy & Security ▸ **Screen Recording** ▸ enable **IN Meetings**,
   then **relaunch**.
4. For the picker (§C): provision the Google Picker key — see **C0**.
5. Have a real call you can join (Zoom / Google Meet) for the capture tests.

---

## A. Reliability

### A1 — VAD is bundled (works with no network)
1. Quit IN Meetings.
2. Delete the provisioned VAD: `rm "~/Library/Application Support/IN Meetings/Models/ggml-silero-v5.1.2.bin"`.
3. **Turn off Wi-Fi** (prove no download is needed).
4. Launch IN Meetings → *expect:* the file **reappears** at that path within a second (copied from the app
   bundle, SHA-verified). Re-enable Wi-Fi.
   - `shasum -a 256` of it should be `29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf`.

### A2 — VAD stops silence hallucination (needs a real call)
1. Record a call where the **remote side is silent** for a stretch (e.g. a solo Meet, or mute the others
   briefly). Stop.
2. Open the meeting in the dashboard → *expect:* **no** hallucinated Hebrew (no "אדוני היושב-ראש…"
   Knesset-style text) over the silent stretch.

### A3 — Pipeline failures are visible (not stuck "processing")
1. Inject a failure: `mv "$(which whisper-cli)" "$(which whisper-cli).bak"` (reversible).
2. Record ~10 s (any audio) and Stop. Wait a few seconds.
3. Dashboard → *expect:* the meeting shows a red **"failed"** chip; opening it shows **"Transcription
   failed"** + the error + a **Reveal pipeline.log** button — and it appears **without reopening the
   window** (live reload). It is **not** stuck spinning in "Processing".
4. Restore: `mv "$(which whisper-cli).bak" "$(which whisper-cli)"`. (A later successful run on the same
   meeting clears the failed state.)

---

## B. Call video capture

### B0 — Setup
- Settings ▸ Recording → **Record call video** is ON. Use **Open Screen Recording settings…** to grant the
  permission, enable IN Meetings, and **relaunch** (the grant takes effect on the next launch — until then
  capture quietly degrades to audio-only).

### B1 — Golden path: capture → mux → playback **(now unified ScreenCaptureKit capture)**
> As of 2026-06-16 a video call captures screen + system audio + mic through **one** SCK stream (one
> clock), so A/V sync is the headline check. `mic.wav`/`system.wav`/`video.mov` are unchanged on disk.
1. Join a call with its window visible. Record (the "Record now" card, or ⌃⌥⌘R). Talk ~30 s, and make sure
   the **remote side also speaks** (so we can confirm "Them" is captured); share a screen if you can. Stop.
2. **Reveal Last Recording** → *expect:* `mic.wav`, `system.wav`, `video.mov` all present; within a few
   seconds `meeting.mp4` appears.
3. Open the meeting → *expect:* the video player shows the call window and **audio is in sync** (lip-sync
   holds for the whole clip, start to end — this is what the rewrite fixes). Tapping a transcript line seeks.
4. **Both sides transcribed?** *expect:* the transcript has **your** speech *and* the **remote** speech
   (confirms SCK's window-scoped `.audio` captured "Them" as well as the old Core-Audio tap did — the one
   thing only a live call can prove). If "Them" is missing/empty, tell me — we keep the tap path as fallback.

### B2 — Drive upload + retention
1. With Drive connected and a folder chosen (§C), let the meeting finish.
2. Check Drive → *expect:* **`meeting.mp4`** is uploaded under `<your folder>/<Company>/<meeting>/`
   (not the raw tracks).
3. Back in the local meeting folder → *expect:* if **"Delete raw tracks after Drive backup"** is on
   (default), `mic.wav`/`system.wav`/`video.mov` are **gone** and `meeting.mp4` + the package **remain**.
   (Turn the setting off to keep raw tracks.)

### B3 — In-person is audio-only
1. Record with **no call** detected (mic-only / in-person). Stop.
2. *Expect:* no `video.mov`/`meeting.mp4`; a merged **`audio.m4a`** only; the detail view shows the audio
   bar, not a video surface.

### B4 — Graceful degradation
1. Revoke Screen Recording (or toggle **Record call video** off) and record a call. Stop.
2. *Expect:* the recording still works **audio-only**, no crash, audio tracks intact.

---

## C. Drive folder picker (real Google Drive web view)

### C0 — Provision the Picker key (one-time, external)
1. Google Cloud Console → project **`1062382667236`** → **APIs & Services ▸ Library** → enable
   **"Google Picker API"**.
2. **APIs & Services ▸ Credentials ▸ Create credentials ▸ API key** → this is a **Browser key**.
3. Restrict it to **HTTP referrers** and add `https://localhost/*`, **or** leave it unrestricted (fine for
   an internal tool — it only loads the Picker UI; data access is still the OAuth token).
4. Provide it to the app: `export GOOGLE_PICKER_API_KEY=<key>` before launch, **or** paste it into
   `DriveConfig.pickerAPIKeyDefault` and rebuild. Relaunch.

### C1 — Connect
1. Settings ▸ Drive → **Connect Google account** → sign in with your IN Venture Google account.
2. *Expect:* the account email shows.

### C2 — Golden path: pick any folder in the web view
1. Click **Choose folder in Google Drive…** → *expect:* a **real Google Drive browser** opens (your My
   Drive + Shared Drives, folders only).
2. Navigate into any folder, select it, confirm → *expect:* the sheet closes and **Backup location** shows
   that folder's name.

### C3 — Shared Drive folder resolves correctly
1. In C2 pick a folder **inside a Shared Drive**.
2. Record + finish a meeting → *expect:* it uploads under **that Shared Drive**, in
   `<picked folder>/<Company>/<meeting>/` (confirms the folder's `driveId` was resolved).

### C4 — Not-configured fallback
1. With **no** key set (unset `GOOGLE_PICKER_API_KEY` + empty `pickerAPIKeyDefault`), click **Choose
   folder…** → *expect:* the sheet shows the **setup steps**, not a blank/broken page.

### C5 — Persistence
1. Quit + relaunch → *expect:* Settings ▸ Drive still shows the chosen backup folder.

---

## Known limitations (by design, this round)
- **A/V sync** is now established at capture via one ScreenCaptureKit clock + real timestamps (the t=0 merge
  is gone). If sync is still off on a long call, that points to SCK audio gaps — flag it.
- **Screen Recording grant** applies on the **next launch**, so the *first* call after granting may be
  audio-only.
- **Retention** prunes raw tracks only *after* a successful Drive backup and only when a merged file exists;
  a global "cap the cache at N GB" is not built yet.
- **Multi-party (3+) diarization** quality is still unproven on a real recording — eyeball the speaker
  labels + `pipeline.log` on the first 3-person call.
