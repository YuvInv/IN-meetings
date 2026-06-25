# Third-Party Notices

INV Meetings incorporates and adapts third-party software. This file documents
each component, its license, and what we changed, as required by those licenses.
See also [`NOTICE`](NOTICE) and [`licenses/`](licenses/).

## Adapted source — Mila (Apache-2.0)

- **Project:** Mila — https://github.com/island-io/mila
- **Copyright:** © 2026 Island Technology, Inc. Originally developed by Uri Harduf.
- **License:** Apache License 2.0 — full text in [`licenses/mila-LICENSE-2.0.txt`](licenses/mila-LICENSE-2.0.txt).
- **What we adapted.** Each derived file carries an `// Adapted from Mila …`
  header that states the changes made, per Apache-2.0 §4(b):
  - `Sources/INMeetingsCore/Models/ModelManager.swift` and
    `Sources/INMeetingsCore/Models/ModelCatalog.swift` — model-download-on-launch
    (URLSession download + streaming SHA-256 verification + atomic install).
    Rewritten for our `@Observable`/`@MainActor` model (Mila used Combine
    `@Published`), reduced to the single Hebrew model we ship, and the CoreML
    encoder download was dropped (inert with the Homebrew `whisper-cli`, which is
    built without CoreML). The installed model feeds the **Python** pipeline via
    the `IN_MEETINGS_MODEL` environment variable, not Swift whisper bindings.
  - `Apps/INMeetings/INMeetings/MeetingPromptOverlay.swift`,
    `Apps/INMeetings/INMeetings/MeetingPromptCoordinator.swift`, and
    `Sources/INMeetingsCore/Detection/MeetingDetectionSettings.swift` — the "Record now"
    meeting-prompt overlay (Harvest 3). Re-skinned in macOS 26 Liquid Glass; driven by our Core Audio
    `CallDetector` (app-agnostic, no Screen Recording) instead of Mila's Zoom-only window-title poll;
    `@Observable`/`@MainActor` rewrite; global snooze keyed on the detector's friendly app name.
  - `Apps/INMeetings/INMeetings/Dashboard/*` and `Apps/INMeetings/INMeetings/Settings/*` — the dashboard +
    settings UX (Harvest 4): a `NavigationSplitView` (sidebar + date-bucketed meeting list + a detail pane
    with an RTL Hebrew transcript, tap-a-line-to-seek, and an AVKit player) and a tabbed Settings scene.
    Rebuilt against our context-package / SQLite index (`MeetingRecord`, `TranscriptPackage`) instead of
    Mila's `Recording`/`RecordingStore`, re-skinned in macOS 26 Liquid Glass, English chrome, `@Observable`
    model. The date-bucketing, in-memory search filter, and the transcript seek-row are the closest adaptations.
  - _Planned (later harvests, this file will be updated as they land):_ in-place
    update relocation (`BundleRelocator`) and `scripts/make-dmg.sh`.

## Runtime dependencies (downloaded/installed, not vendored in this repo)

- **Whisper model weights** — `ivrit-ai/whisper-large-v3-turbo-ggml`, downloaded
  at first launch from Hugging Face. See the model card for its license.
- **whisper.cpp** (MIT) — local ASR inference (`whisper-cli`), installed via Homebrew.
- **senko** (MIT) — speaker diarization, installed into the pinned Python venv.

> **Sparkle** (MIT), used for auto-update, will be added to this file when
> Harvest 2 (packaging + auto-update) lands.
