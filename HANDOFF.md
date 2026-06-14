# Agent Handoff — IN-meetings

<!--
Rewritten at every handoff. The incoming agent reads this + DECISIONS.md before starting.
Keep it short: last state, next steps, gotchas. History lives in git log.
-->

## Outgoing Agent
Claude Code · 2026-06-14

## Current State
**MVP Phase 1 spine is complete + the context-package contract is frozen + Drive sync is built.**
- Slices **1–4c + H0/H1/H3 + slice 5 (context package + SQLite index)** are **merged to `main`** (PRs #1–#4).
- **Slice 5 is LIVE-VERIFIED** on a real Google Meet call (DB row: call / 2 speakers / real timestamps /
  `capture_source_app`). The detect → record → transcribe → diarize → **package → index** chain works end-to-end.
- **Slice 6 (Drive sync) is code-complete on branch `feat/slice-6-drive-sync`** (uncommitted/just-committed —
  see git log): **42 Swift tests green, `make build-mac` green**, but the **interactive Google sign-in is not
  yet live-verified** (needs a real account).

### This session (2026-06-14): slice 5 live-verify + merge, then slice 6 — Drive sync
- **Slice 5** committed (PR #4), live-verified on a real call, merged.
- **Slice 6** built (DECISIONS 2026-06-14), **Swift-owned** (amends ADR-009) with a **per-user dynamic backup
  location** (refines ADR-006 — each user connects their own account + picks their Drive; nothing hardcoded
  except the OAuth client id in `DriveConfig`). All in `Sources/INMeetingsCore/Drive/`:
  - `PKCE` + `GoogleOAuth` (auth URL + token bodies) · `GoogleTokenService` (live POST) · `DriveCredential` +
    `KeychainTokenStore` (refresh-token carry-forward) · `DriveTokenManager` (refresh) · `DriveClient`
    (Shared-Drive-aware: list drives, find/create folder, multipart upload, `accountEmail`) ·
    `DriveLocationStore` · `DriveSync` (`<Company>/<meeting>/`, idempotent) · `DriveBackup` wired into
    `JobBridge` to auto-upload on `done`.
  - App target: `DriveAuth` (`ASWebAuthenticationSession` sign-in + Shared-Drive picker) + a menu section in
    `INMeetingsApp.swift` (Connect / account / choose location / disconnect); `Info.plist` registers the
    reversed-client-id redirect scheme.
  - **Scope**: text package uploads one-shot + the **recordings (mic/system.wav, video.mov) stream via a
    resumable session** (per Yuval). Fills the index's `driveFolderId`/`syncState`.

## Next — START HERE
- **⏳ LIVE-VERIFY slice 6 (needs you):** run the app → menu **"Connect Google Drive…"** → sign in with an
  IN Venture account → **choose a Shared Drive** as the backup location → record a short meeting → confirm an
  `<Company>/<meeting>/` folder with the text files appears in that Drive, and the index row flips to
  `syncState=synced`. **Watch the sign-in sheet:** the `ASWebAuthenticationSession` anchor in a menu-bar
  (`LSUIElement`) app is the known-risky bit — if the consent window doesn't appear, ping me and I'll switch
  to a browser-redirect (the URL scheme is already registered) or fix the anchor.
- Then **commit/merge** slice 6 (PR open) and move to **Phase 2 — context assembler + biasing** (the
  differentiator: Calendar + Saventa + Dealigence → ASR vocab + `context.md`; flips `metadata.transcription.
  biased` + populates `attendees`/`company`/`context.sources`, all of which the schema already reserves).
- Additive harvests (V1 call video, V2 auto-stop, H4 dashboard, H2 Sparkle) remain off the spine's path.
- **Skills `--package` adapter** (ADR-005 part 2, Phase 3): coordinated change in `~/repos/claude-skills` —
  mirror `schema/fixtures/golden-package/`.

## Gotchas (verified)
- **New *app-target* files need `make gen`** before `make build-mac` — XcodeGen only auto-regenerates when
  `project.yml` changes, not when you add a source file under `Apps/INMeetings/INMeetings/`.
- **`ASWebAuthenticationSession` in a menu-bar app** has no natural window anchor (`AuthAnchor` falls back to
  a transient `NSWindow`) — verify the sheet actually presents; browser-redirect is the fallback.
- **@Observable + `lazy`** → mark non-observed stored props `@ObservationIgnored` (else the macro makes them
  computed and `lazy` won't compile). Pure helpers called from tests off the main actor need `nonisolated`.
- (carried) pipeline tests run from `pipeline/` (or `PYTHONPATH=pipeline`); `metadata.py` reads WAV info via
  soundfile (float32); senko needs the pinned 3.11 venv; **TCC grant needs a relaunch**; tap write is
  interleaved float32 (−50 otherwise); pipeline is spawned, not compiled in; model download → `IN_MEETINGS_MODEL`.

## Open / follow-ups
- **⚠️ PRE-ROLLOUT (DECISIONS 2026-06-14): single merged playback file.** Before team rollout, merge the dual
  tracks into one playback artifact — `audio.wav` (mic+system, level-balanced) for audio, `meeting.mp4`
  (video+audio muxed) for video calls — via an **AVFoundation render step in the app, kicked at Stop,
  concurrent with transcription**. Keep the separate tracks as transcription inputs; Drive backup then uploads
  the **merged** file instead of the separate tracks; the dashboard (H4) plays it. Listeners get the full
  experience without seeing the recording channels.
- (carried) **⏳ multi-party-call diarization quality** untested on a real 3+ call (MVP-accepted) — review the
  per-meeting `pipeline.log`.
- SourceKit shows stale "Cannot find type … / No such module GRDB" squiggles after new files land until it
  reindexes — cosmetic; `swift test` + `make build-mac` are the ground truth.
- (carried) pyannote fallback not wired; onboarding TCC wizard minimal; Soniox fallback; ADR-010 counsel review.
- Slice 6 follow-ups: a **retention/size cap** for the uploaded recordings (ADR-010 — they're GB-scale);
  tighten the Drive scope to `drive.file` if per-user ownership changes; a `qa-slice6` script.

## Context
- Env: macOS 26 / M3+/16GB. Local cache under `~/Library/Application Support/IN Meetings/` (`Recordings/`,
  `Models/`, `meetings.db`); Drive = per-user OAuth (client id in `DriveConfig`), each user picks the destination.
- Pipeline dev paths hardcoded in `JobBridge` (overridable via env); Phase 5 bundles the pipeline + a sealed env.
- Downstream skills call the Timeless API directly today — the context package is a NEW contract (ADR-005).
