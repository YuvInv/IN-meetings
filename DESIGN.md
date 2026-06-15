# DESIGN — IN-Meetings

**Native macOS meeting recorder + Hebrew transcription pipeline for IN Venture.**
Phase-2 deliverable. Every decision below has a dedicated ADR in [`adr/`](adr/) with options and
tradeoffs; this document is the spine that ties them together. Research backing is in
[`RESEARCH.md`](RESEARCH.md).

> **Status (updated 2026-06-15):** ✅ **Built and shipping** — Phase-0 + the MVP spine are merged to `main`
> and the app runs end-to-end (detect → dual-track capture → on-device Hebrew transcription → diarization →
> context package → Drive backup → dashboard). This document is the **original design spine**; several
> decisions have since evolved (recorded in [`DECISIONS.md`](DECISIONS.md) and the per-ADR "Amended"
> banners). **Live, ordered priorities:** [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) → "Road to a
> team-ready v1". Key deltas vs. the text below: **(1)** the app is a **hybrid Dock-icon app + menu-bar
> tray**, not a pure `LSUIElement` agent (amends ADR-001/009); **(2)** **call video is ON by default**
> (ScreenCaptureKit window-only, HEVC) and is a **P1** item, not "off by default" (amends ADR-002);
> **(3)** **Saventa + Dealigence context is deferred to Phase 6** — the live context layer is **Google
> Calendar only** (amends ADR-004); **(4)** the Claude→CRM auto-trigger is in scope (**P1**) but an in-app
> **"AI overview" panel is out of scope for v1**.

---

## 1. What we're building (one paragraph)

A macOS app (a hybrid Dock-icon app + menu-bar tray) that silently detects when you're in a meeting (Zoom, Google Meet, Teams, Slack
huddles, generic calls), records **mic and remote audio as two separate tracks** locally — no bot, no
virtual driver, invisible to other participants — and, *before* transcribing, assembles context about
who's in the room (Google Calendar) and what we know about them (Saventa CRM + Dealigence). That
context becomes (a) a biasing vocabulary fed to an on-device Hebrew ASR model to fix founder/company
names and code-switched English terms, and (b) a `context.md` in the output. The result is a
per-meeting **context package** — a folder with audio, transcript, context, and metadata — that syncs
to the team Google Drive and flows directly into the existing Claude skills (`saventa-summary`,
`generate-mom`, `process-meeting`, `enrich-company`). One trigger, not five manual steps.

The edge is **context injection + tight Claude integration**, not raw ASR. The research confirms this
territory is unoccupied: no shipping competitor combines local processing + Hebrew + vocabulary biasing.

## 2. Constraints (non-negotiable, from the brief)

- macOS native only; **no meeting bots**; invisible to other participants.
- Apple Silicon; team floor **macOS 26 (Tahoe), M3/16GB** (confirmed) → full API surface available.
- **No virtual audio drivers** — ScreenCaptureKit / Core Audio process taps only.
- Confidential founder/deal data → **on-device processing by default**; any cloud ASR is opt-in and documented.
- Output must be **Claude-skill-ready** — the context package is the stable contract.

## 3. Architecture at a glance

```
                          ┌──────────────────────────────────────────────┐
   menu-bar agent (Swift) │  IN-Meetings.app  (LSUIElement, launch-at-login)│
                          └──────────────────────────────────────────────┘
                                          │
        detect ──► banner ──► capture ──► (meeting ends) ──► hand off folder
          │           │          │
   Core Audio    NSPanel    Tap (remote/system audio)  +  AVAudioEngine (mic)
   mic-in-use   .nonactiv.  ── two separate WAV tracks ──┐
   + calendar    over           video optional (SCK, off by default)
   + app/tab     fullscreen                              │
                                                         ▼
                          ┌──────────────────────────────────────────────┐
                          │  Pipeline (Python, on-device)                  │
                          │  1. context assembler (Calendar+Saventa+       │
                          │     Dealigence → biasing vocab + context.md)   │
                          │  2. ASR (ivrit.ai Whisper turbo, biased)       │
                          │  3. diarization (system track) + Me/Them merge │
                          │  4. write context package                      │
                          └──────────────────────────────────────────────┘
                                          │                    │
                              local SQLite + folder      Google Drive (per-user OAuth)
                                          │                    │
                              SwiftUI dashboard        Claude auto-trigger (claude -p)
                                                       → saventa-summary → MoM → enrich
```

Two processes: a **Swift/SwiftUI menu-bar app** (detection, capture, UI, orchestration) and a
**Python pipeline** (context assembly, ASR, diarization, packaging, Drive, Claude trigger). They
communicate over a local job protocol — see [ADR-009](adr/ADR-009-app-architecture-ipc.md).

## 4. Decision index (ADRs)

| ADR | Decision | Recommendation in one line |
|-----|----------|----------------------------|
| [001](adr/ADR-001-call-detection-trigger-ux.md) | Call detection & trigger UX | Multi-signal detect (mic-in-use ∪ running-app ∪ calendar ∪ browser-tab); **prompt-to-record** via non-activating `NSPanel` over fullscreen; menu-bar `LSUIElement`; ring-buffer so nothing is lost pre-confirm. |
| [002](adr/ADR-002-capture-pipeline.md) | Capture | **Core Audio process tap** (remote/system) + **AVAudioEngine** (mic) as **two WAV tracks**; raw mic + offline AEC; **video off by default** (SCK + HEVC, opt-in); meeting-end on mic-idle debounce. |
| [003](adr/ADR-003-transcription-engine.md) | Transcription | **`ivrit-ai/whisper-large-v3-turbo`** on whisper.cpp Metal (GGML) primary, MLX optional; `initial_prompt` biasing; **senko** diarization on the system track; `transcript.json` + `.txt`; **Soniox** opt-in cloud fallback; slide OCR opt-in via Vision. |
| [004](adr/ADR-004-context-assembler.md) | Pre-transcription context | Match active meeting → Calendar event → Saventa + Dealigence; emit **biasing vocabulary** + `context.md`; graceful degradation when unmatched. |
| [005](adr/ADR-005-context-package-contract.md) | Package contract + skill integration | Freeze the package schema as the contract; add a **`--package <path>` local-input mode** to `saventa-summary`/`generate-mom`/`process-meeting` alongside the Timeless path. |
| [006](adr/ADR-006-storage-drive-sync.md) | Storage & Drive | Local SQLite + per-meeting folder (cache); **Google Drive shared drive via per-user OAuth** as durable source of truth; `/<Company>/<YYYY-MM-DD-…>/` layout. |
| [007](adr/ADR-007-dashboard.md) | Dashboard | **SwiftUI window in the same app** over the SQLite store — list/search/play/open-in-Drive/re-run skill. |
| [008](adr/ADR-008-claude-auto-trigger.md) | Claude auto-trigger | Headless `claude -p` chain, **configurable per meeting** (auto vs one-click), default one-click; meeting-type routing decides which skills run. |
| [009](adr/ADR-009-app-architecture-ipc.md) | App architecture & IPC | Swift menu-bar app + bundled Python venv; **file-based job queue + JSON status** (simple, observable, crash-safe); onboarding wizard for the 4 TCC grants. |
| [010](adr/ADR-010-privacy-consent.md) | Privacy & consent | On-device default; nothing leaves the Mac except to the team Drive (and opt-in cloud/Claude); consent metadata + jurisdiction nudge + retention controls; do-not-record defaults for internal events. |
| [011](adr/ADR-011-recording-modes.md) | Recording modes | **Manual Start** (menu bar + hotkey) as fallback + primary path for **in-person** meetings; manual **auto-picks profile** (call→dual-track, else→mic-only); in-person = mic-only with **per-speaker diarization** on one track; in-person is manual-only (no calendar auto-prompt). |

## 5. The context package (the contract)

```
/<Company>/<YYYY-MM-DD-meeting[-N]>/
  audio_mic.wav            # user side (raw); for in-person, the whole room
  audio_system.wav         # remote participants (tap) — ABSENT for in-person meetings
  video.mov                # optional, HEVC, off by default
  transcript.json          # utterances {text,start,end,speaker_id,confidence}; speakers[]; language
  transcript.txt           # clean, speaker-named, readable
  context.md               # calendar + Saventa + Dealigence priors (clearly marked as priors)
  slides_ocr.md            # optional, screen-share text extraction
  metadata.json            # meeting, attendees(side), company(+sevanta_deal_id), recording, transcription, consent
```

Full field spec and the rationale for each field (driven by what the downstream skills actually need)
are in [ADR-005](adr/ADR-005-context-package-contract.md) and
[`docs/notes/skill-contracts.md`](docs/notes/skill-contracts.md).

## 6. End-to-end flow

1. **Start** — either **auto** (Core Audio detects a live call → "Record now?", ADR-001) or **manual**
   (menu-bar button / hotkey — fallback for missed calls, and the path for in-person meetings; ADR-011).
   Manual auto-picks the profile: live call → dual-track; otherwise → in-person mic-only.
2. **Banner** — non-activating panel: "Recording <Company> — Stop / Pause / Don't record". Ring-buffer
   means the seconds before the user clicks are not lost.
3. **Capture** — call: two tracks (mic + system). In-person: mic only. Optional video.
4. **Context assembly (parallel with capture)** — match to a calendar event; pull Saventa + Dealigence;
   build biasing vocab + `context.md`. Degrade gracefully if unmatched.
5. **Meeting end** — mic idle past debounce → stop → package the raw folder.
6. **Transcribe** — ivrit.ai turbo with the biasing prompt; diarize the system track; merge Me/Them.
7. **Package** — write transcript.json/.txt + metadata.json; assemble the folder.
8. **Sync** — copy to the team Drive; record in SQLite.
9. **Claude** — per config: one-click (default) or auto → `saventa-summary` (+ optional MoM, enrich);
   results written back into the folder and Drive.
10. **Dashboard** — the meeting appears; play, read, jump to Drive, re-run a skill.

## 7. Riskiest unknowns (prototype first — see IMPLEMENTATION_PLAN.md)

1. **Hebrew + code-switching ASR quality** with/without biasing, on real past-meeting audio.
2. **Process-tap + dual-track capture** reliability and the **no-monthly-nag** claim on Tahoe; banner
   over fullscreen Zoom/Meet.
3. **Reliable Meet/browser-tab detection** (AppleScript Automation route; AirPods blind spot).

## 8. Non-goals (YAGNI)

Live/streaming transcription (batch post-meeting is enough for v1; ONNX path noted for later); per-name
diarization of remote speakers beyond what calendar + 2-track gives; sentiment/engagement analytics;
audio clip sharing; Windows/Linux; App Store distribution (internal signing only — lets us use the
private TCC SPI for the audio-permission check). Also out of scope for v1: an **in-app "AI overview" panel** —
the Claude→CRM auto-trigger (P1) writes the summary to Saventa rather than rendering it in the app.
