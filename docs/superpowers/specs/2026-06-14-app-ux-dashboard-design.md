# App UX slice 1 — merged playback file + mila-faithful Liquid Glass dashboard + settings

**Date:** 2026-06-14 · **Author:** Claude Code (UX direction by Yuval) · **Status:** Approved (design), pending spec review
**Implements:** the PLANNED merged-playback-file decision (DECISIONS 2026-06-14) + **mila Harvest 4** (dashboard/settings) + ADR-007
**Supersedes:** ADR-007's "standard SwiftUI / system materials" aesthetic → **Liquid Glass** (DECISIONS 2026-06-14, [[ux-liquid-glass]])
**Reference (Apache-2.0, attributed):** `island-io/mila` — `Mila/Views/{ContentView,SidebarView,HistoryListView,RecordingDetailView,SettingsView}.swift`

---

## 1. Why / background

The app records + transcribes meetings but has **no window to browse, read, or listen** to past ones (only a menu-bar dropdown + the "Record now" overlay + the SQLite index). This slice builds the **dashboard + settings** (ADR-007 / mila Harvest 4) in macOS 26 **Liquid Glass**, modelled on mila's actual UX, with a complementary menu-bar icon.

Decided in brainstorming (2026-06-14), refined after reading mila's source:
- **Structure = mila-faithful** `NavigationSplitView` (sidebar + content), **not** a bare two-pane.
- **Audio:** build the **single merged playback file first** (mila plays one file per recording — validates this).
- **Settings included** in this slice (tabbed scene, modelled on mila's `SettingsView`).
- **Language:** the **entire app UI is English**; only transcript *content* is Hebrew (RTL).

## 2. Goal & non-goals

**Goal:** finishing a meeting produces one merged audio file; a Liquid Glass window (sidebar + content) lets you browse meetings (date-bucketed list), open one (detail), read its **RTL Hebrew transcript** (speaker-named) and **listen with tap-a-line-to-seek**, **search** in-memory, and adjust **settings** (detection, model, Drive).

**Non-goals (deferred):** company **folders** + drag-drop, **trash**/soft-delete, the **AI overview** (that's our Phase-3 Claude-skills output), re-transcribe / export-SRT / send-to-LLM actions, FTS5 (in-memory filter suffices at our scale), Audio-input-device + Storage + Updates(Sparkle) + Hotkey-rebind settings tabs, and **video** (capture V1 isn't built; player is audio-only — the renderer is structured so `meeting.mp4` slots in later).

**Done when:** a real meeting renders `audio.m4a`; the dashboard lists it (date-bucketed), opens detail, renders Hebrew RTL, tap-a-line seeks the merged audio; search filters; the three settings tabs work; Drive receives the merged file.

## 3. Design constraints
- **English UI chrome** everywhere; Hebrew only in transcript content, **RTL** (`.environment(\.layoutDirection, .rightToLeft)` on the transcript scroll, like mila `RecordingDetailView:277`).
- **Liquid Glass** (macOS 26): `.glassEffect()` / `GlassEffectContainer` / glass button styles (the project already uses these in `MeetingPromptOverlay`). **Honor Reduce Transparency.** mila uses `.regularMaterial` cards; we substitute glass. App target = macOS 26; `INMeetingsCore` stays `.macOS(.v14)`, so all SwiftUI lives in the app target.
- `@MainActor @Observable` (no Combine — mila uses `@EnvironmentObject`/Combine; we rewrite to Observation, as we did for the harvested `ModelManager`/overlay).

## 4. Component 1 — Merged playback file *(foundation, built first)*

Unchanged from the prior design. On **Stop**, render one **level-balanced** `audio.m4a` (AAC) from `mic.wav` + `system.wav`, **concurrently with the pipeline** (`RecordingController.stop():124`, alongside `jobBridge.enqueue`, in a background `Task`).
- `Sources/INMeetingsCore/Capture/PlaybackRenderer.swift`: `balancedVolumes(micRMS:systemRMS:)` (pure, tested) → measure each track's RMS, set `AVMutableAudioMix` volumes (quieter boosted ≤4×, louder = 1.0); `AVMutableComposition` (handles 24 kHz mic vs 48 kHz system) → `AVAssetExportSession(.appleM4A)` → `<meeting>/audio.m4a`. In-person (mic-only) → transcode the single track.
- **Drive (amends slice 6):** `DriveSync.mediaFileNames(in:)` uploads `audio.m4a` (the listen artifact) instead of `mic.wav`/`system.wav`; falls back to the raw tracks if the render failed. AAC m4a (not WAV) — small for Drive, AVFoundation-native; raw WAVs stay as the lossless transcription inputs.
- **Fail-soft:** render failure → no `audio.m4a`; the detail shows the transcript with no player; Drive falls back to raw tracks. Never blocks Stop/pipeline.

## 5. Component 2 — Dashboard window *(mila-faithful)*

A Liquid Glass `Window` scene opened from the menu, a **`NavigationSplitView`** (adapt mila `ContentView`). New group `Apps/INMeetings/INMeetings/Dashboard/`:

- **`RecordingStore.swift`** — `@MainActor @Observable` reader over the ADR-006 SQLite index (`MeetingStore.allMeetings()` → `[MeetingRecord]`); the selected meeting; loads `TranscriptPackage` + `MeetingMetadata` via `PackageReader` from the meeting's `folderPath`; the merged `audio.m4a` URL. **Not** a port of mila's store.
- **`DashboardWindow.swift`** — the `NavigationSplitView` shell (adapt mila `ContentView`): `.searchable` in the toolbar (in-memory filter), sidebar + content switch on a `DashboardSelection` enum (`.allMeetings`, `.needsLinking`, `.processing`, `.meeting(id)`).
- **`DashboardSidebar.swift`** — `List(selection:)` (adapt mila `SidebarView`): **All Meetings** · **Needs linking** (`company.matched == false`) · **Processing** (pipeline running / `syncState`/`status`) + a footer `SettingsLink` (`Cmd+,`). Liquid Glass sidebar.
- **`MeetingListView.swift`** — **date-bucketed** list (adapt mila `HistoryListView`/`BucketedRecordingsView`/`bucketByDate`): Today / Yesterday / weekday / older; each bucket a glass card of `MeetingRow`s.
- **`MeetingRow.swift`** — source/type badge + company + title + **transcript preview** (2 lines) + duration + time + **status chips** (call/in-person · synced · context · `link?`); hover/select highlight; tap → `.meeting(id)`.
- **`MeetingDetailView.swift`** — adapt mila `RecordingDetailView`: header (company + matched/deal badge, source, date, duration; actions: **Copy transcript**, **Reveal in Finder**, **Open in Drive**) → transcript → playback bar. (mila's AI-overview / re-transcribe / export-SRT / share are deferred.)
- **`TranscriptSegmentView.swift`** — adapt mila `SegmentRow`: from `TranscriptPackage.utterances[]` + `speakers[]`; speaker name (friendly, internal/external color), text, timestamp; **active-line highlight** when `currentTime ∈ [start,end)`; **tap → seek**. Parent sets `.environment(\.layoutDirection, .rightToLeft)`.
- **Player:** `AVPlayer` on `audio.m4a` + a 30 fps periodic time observer driving the active line + slider; play/pause via KVO on `timeControlStatus` (mila `PlayPauseButton`).

**In-memory search** (adapt mila `filterRecordings`): filter meetings by company / title / transcript text — no FTS5.

**Entry + scenes:** `INMeetingsApp` gains `Window("Dashboard", id: "dashboard")`; the menu gets **"Open Dashboard"** → `openWindow(id: "dashboard")`. New app-target files ⇒ **`make gen`**.

**Degradation:** no `transcript.json` → "No transcript yet" (`ContentUnavailableView`); no `audio.m4a` → transcript only, player hidden.

**Tests:** `RecordingStore` over a temp SQLite + fixture folder (list mapping, transcript/metadata load); pure helpers — `bucketByDate`, `filterMeetings`, `activeUtteranceIndex(at:)`, the `needsLinking`/`processing` predicates. (SwiftUI + AVKit live-verified.)

## 6. Component 3 — Settings scene *(mila-faithful, tabbed)*

A standard `Settings` scene (`Cmd+,`, `SettingsLink` in the sidebar footer) — a `TabView` ~560×560 (adapt mila `SettingsView`), three tabs (reusing existing state):
- **Recording** (adapt mila `MeetingsSettingsTab`) — `MeetingDetectionSettings`: "Prompt to record detected calls" toggle, snooze, supported/silenced apps; show the global hotkey (⌃⌥⌘R).
- **Model** (adapt mila `ModelsSettingsTab`) — `ModelManager` status for the ivrit-turbo model + the Silero VAD model: installed / downloading%/ verify / retry.
- **Drive** — connect/disconnect the Google account + choose the backup Shared Drive (move the existing `DriveAuth` `driveSection` out of the menu into this tab).

Deferred tabs (mila has them, we don't yet): Audio input device, Storage/retention, Updates (Sparkle, H2), Hotkey rebinding, LLM/Live-AI (not our model). **Tests:** none beyond the existing settings-model tests (SwiftUI live-verified).

## 7. Component 4 — Menu-bar icon + entry
- **"Open Dashboard"** menu item.
- The menu-bar icon reads state in the waveform family (idle `waveform` / armed tinted / recording red-dot+timer) so it complements the window. Small refinement of `INMeetingsApp`'s label.

## 8. Data flow
```
Stop ─┬─ JobBridge.enqueue ─→ pipeline ─→ transcript.json / metadata.json / SQLite index   (minutes)
      └─ PlaybackRenderer.render(mic,system) ─→ audio.m4a                                    (seconds)
Dashboard ── RecordingStore ──reads── SQLite index (list) + PackageReader (detail) + audio.m4a (player)
Drive backup (on 'done') ── uploads ── package text + audio.m4a  (raw tracks only if render failed)
```

## 9. File structure
- **Create:** `Sources/INMeetingsCore/Capture/PlaybackRenderer.swift`; `Apps/INMeetings/INMeetings/Dashboard/{RecordingStore,DashboardWindow,DashboardSidebar,MeetingListView,MeetingRow,MeetingDetailView,TranscriptSegmentView}.swift`; `Apps/INMeetings/INMeetings/Settings/{SettingsView,RecordingSettingsTab,ModelSettingsTab,DriveSettingsTab}.swift`; tests `Tests/INMeetingsCoreTests/{PlaybackRendererTests,RecordingStoreTests,MeetingBucketingTests}.swift`.
- **Modify:** `RecordingController.stop()` (kick the render); `DriveSync` (`mediaFileNames(in:)` + m4a/mp4 mime); `INMeetingsApp.swift` (Dashboard `Window` + Settings scene + "Open Dashboard" + icon states; move `driveSection` to the Drive tab); `make gen`.
- **Attribution:** every mila-derived file gets the `// Adapted from Mila …` Apache-2.0 header (per existing `ModelManager`/`MeetingPromptOverlay`) + `THIRD_PARTY_NOTICES.md`.

## 10. Build order (staged, each committable + verifiable)
1. **Merged file** (PlaybackRenderer + Stop kick + Drive switch) → `audio.m4a` renders + uploads.
2. **Dashboard shell + list** (RecordingStore, NavigationSplitView, sidebar, date-bucketed list + search) in Liquid Glass.
3. **Detail** (transcript RTL + tap-to-seek + merged-audio player + copy/reveal/open-in-Drive).
4. **Settings** (Recording / Model / Drive tabs).
5. **Icon + entry**.

## 11. Verification (verify-each-slice)
- Unit: PlaybackRenderer balance + render; RecordingStore mapping; `bucketByDate`; `filterMeetings`; `activeUtteranceIndex`. `swift test` + `make build-mac` green.
- **Live:** record a real call → `audio.m4a` plays; dashboard lists it date-bucketed with chips; detail renders **Hebrew RTL**, **tap-a-line seeks**, the playing line highlights; `Needs linking` shows unmatched; search filters; the 3 settings tabs work (toggle detection, see model status, connect Drive); Drive has `audio.m4a`; Reduce Transparency → glass falls back.

## 12. Decisions to record (DECISIONS.md)
- Merged playback file (`audio.m4a`, AAC, level-balanced, AVFoundation at Stop, concurrent); Drive uploads it. Video deferred.
- Dashboard + Settings = **mila-faithful** (NavigationSplitView + sidebar + date-bucketed list + tabbed settings), **Liquid Glass**, **English chrome / Hebrew RTL**; supersedes ADR-007's "standard materials"; in-memory search (no FTS5 yet).
- Deferred: folders/drag-drop, trash, AI overview, re-transcribe/export/send-to-LLM, extra settings tabs, video, FTS5.

## 13. Open follow-ups
Folders + drag-drop; trash/soft-delete; FTS5 at scale; AI overview (Phase-3 skills); re-transcribe / export-SRT; more settings tabs (Audio device, Storage/retention, Updates/Sparkle, Hotkey rebind); **video** capture (V1) + `meeting.mp4` playback; retention/size cap once the merged file is the kept artifact.
