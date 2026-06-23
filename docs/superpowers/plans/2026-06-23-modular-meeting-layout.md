# Modular / Resizable Meeting Layout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `MeetingDetailView` a side-by-side, drag-resizable layout — a left context column (video + collapsible summary) beside a full-height transcript — with divider sizes and summary visibility persisted globally.

**Architecture:** A pure clamp-math helper `SplitLayout` in Core (unit-tested) backs a reusable Liquid-Glass `ResizableSplit` SwiftUI view in the app target. `MeetingDetailView` is recomposed from its fixed `VStack` into a tree of `ResizableSplit`s, computed from whether the meeting has video and whether the summary is shown. Persistence is `@AppStorage` (the app's existing idiom).

**Tech Stack:** Swift / SwiftUI (macOS 26, Liquid Glass), AppKit (`NSCursor`, `AVPlayerView`), XCTest, XcodeGen + xcodebuild (`make`).

**Spec:** `docs/superpowers/specs/2026-06-23-modular-meeting-layout-design.md`

---

## File Structure

- **Create** `Sources/INMeetingsCore/Dashboard/SplitLayout.swift` — pure divider-fraction clamp math. No SwiftUI. The only unit-tested logic.
- **Create** `Tests/INMeetingsCoreTests/SplitLayoutTests.swift` — XCTest for the clamp math.
- **Create** `Apps/INMeetings/INMeetings/Dashboard/ResizableSplit.swift` — reusable two-pane drag splitter (Liquid Glass), persists its fraction via an injected `@AppStorage` key. Uses `SplitLayout`.
- **Modify** `Apps/INMeetings/INMeetings/Dashboard/MeetingDetailView.swift` — recompose the body into `ResizableSplit`s; relocate `speakerLegend` into the transcript column; rewrite `summaryPanel` → `summaryPane` to fill its pane (drop the 220pt cap + internal `Divider`s); add a `showSummaryPane` `@AppStorage` toggle to the header.
- **Modify** `HANDOFF.md`, `DECISIONS.md` — record the feature.
- **Create** `docs/manual-tests-modular-layout.md` — the live-verification checklist.

**Build mechanics:** `SplitLayout.swift` (Core) is picked up by SPM automatically — verify with `swift test`. `ResizableSplit.swift` is a NEW app-target file → run `make gen` before `make build-mac`.

---

### Task 1: `SplitLayout` pure clamp math (Core, TDD)

**Files:**
- Create: `Sources/INMeetingsCore/Dashboard/SplitLayout.swift`
- Test: `Tests/INMeetingsCoreTests/SplitLayoutTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/INMeetingsCoreTests/SplitLayoutTests.swift`:

```swift
import XCTest
@testable import INMeetingsCore

final class SplitLayoutTests: XCTestCase {
    func testFractionWithinRangeIsUnchanged() {
        // total 1000, mins 240/320 → legal range [0.24, 0.68]; 0.38 is inside.
        XCTAssertEqual(SplitLayout.clampFraction(0.38, total: 1000, min0: 240, min1: 320),
                       0.38, accuracy: 1e-9)
    }
    func testClampsBelowFirstMinimum() {
        XCTAssertEqual(SplitLayout.clampFraction(0.10, total: 1000, min0: 240, min1: 320),
                       0.24, accuracy: 1e-9)   // min0/usable
    }
    func testClampsAboveSecondMinimum() {
        XCTAssertEqual(SplitLayout.clampFraction(0.90, total: 1000, min0: 240, min1: 320),
                       0.68, accuracy: 1e-9)   // 1 - min1/usable
    }
    func testTooSmallToHonorBothMinsSplitsProportionally() {
        // usable 400 < 240+320 → proportional: 240/560.
        XCTAssertEqual(SplitLayout.clampFraction(0.50, total: 400, min0: 240, min1: 320),
                       240.0 / 560.0, accuracy: 1e-9)
    }
    func testNonFiniteFractionFallsBackToHalf() {
        XCTAssertEqual(SplitLayout.clampFraction(.nan, total: 1000, min0: 240, min1: 320),
                       0.5, accuracy: 1e-9)
    }
    func testZeroTotalIsSafe() {
        XCTAssertEqual(SplitLayout.clampFraction(0.38, total: 0, min0: 240, min1: 320),
                       0.5, accuracy: 1e-9)
    }
    func testDividerThicknessReducesUsableLength() {
        // usable = 1000 - 10 = 990; loFrac = 240/990.
        XCTAssertEqual(SplitLayout.clampFraction(0.0, total: 1000, min0: 240, min1: 320, divider: 10),
                       240.0 / 990.0, accuracy: 1e-9)
    }
    func testFirstLength() {
        XCTAssertEqual(SplitLayout.firstLength(fraction: 0.5, total: 1000), 500, accuracy: 1e-9)
        XCTAssertEqual(SplitLayout.firstLength(fraction: 0.5, total: 1000, divider: 10),
                       495, accuracy: 1e-9)
        XCTAssertEqual(SplitLayout.firstLength(fraction: 0.5, total: 0), 0, accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SplitLayoutTests`
Expected: FAIL — `cannot find 'SplitLayout' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/INMeetingsCore/Dashboard/SplitLayout.swift`:

```swift
import Foundation

/// Pure geometry for a two-pane draggable splitter — no SwiftUI, so it is unit-testable.
/// `fraction` is the FIRST pane's share of the usable length (`total` minus the divider thickness),
/// in 0...1.
public enum SplitLayout {
    /// Clamp a requested divider `fraction` to a legal value: each pane keeps at least its minimum
    /// length. If the container is too small to honor both minimums, the panes split the usable length
    /// proportionally to their minimums. Never returns NaN or a value outside 0...1.
    public static func clampFraction(_ fraction: Double, total: Double, min0: Double, min1: Double,
                                     divider: Double = 0) -> Double {
        let usable = total - divider
        guard usable > 0 else { return 0.5 }
        if min0 + min1 >= usable {
            let denom = min0 + min1
            return denom > 0 ? min0 / denom : 0.5
        }
        let loFrac = min0 / usable
        let hiFrac = 1 - (min1 / usable)
        let f = fraction.isFinite ? fraction : 0.5
        return Swift.min(Swift.max(f, loFrac), hiFrac)
    }

    /// The first pane's length in points for `fraction` of the usable length (`total` minus `divider`).
    public static func firstLength(fraction: Double, total: Double, divider: Double = 0) -> Double {
        Swift.max(0, (total - divider) * fraction)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SplitLayoutTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/INMeetingsCore/Dashboard/SplitLayout.swift Tests/INMeetingsCoreTests/SplitLayoutTests.swift
git commit -m "feat(core): SplitLayout pure clamp math for resizable panes"
```

---

### Task 2: `ResizableSplit` reusable splitter view (app target)

**Files:**
- Create: `Apps/INMeetings/INMeetings/Dashboard/ResizableSplit.swift`

This is a SwiftUI view — there is no unit-test harness for layout in this project, so the verification is a green app build (per the spec, build-green is a gate but not final acceptance; the live run in Task 4 is acceptance).

- [ ] **Step 1: Create the view**

Create `Apps/INMeetings/INMeetings/Dashboard/ResizableSplit.swift`:

```swift
import SwiftUI
import AppKit
import INMeetingsCore

/// A reusable two-pane splitter with a draggable handle. Persists the FIRST pane's fraction of the
/// container via an injected `@AppStorage` key, so divider positions survive relaunch. Chrome stays
/// LTR (the divider math is not RTL-mirrored); only pane *content* may be RTL. The clamp math lives in
/// Core (`SplitLayout`) and is unit-tested.
struct ResizableSplit<First: View, Second: View>: View {
    enum Axis { case horizontal, vertical }

    private let axis: Axis
    private let min0: Double
    private let min1: Double
    private let first: First
    private let second: Second
    @AppStorage private var fraction: Double
    @State private var dragStartFraction: Double?

    private let handleThickness: Double = 7

    init(axis: Axis, min0: Double, min1: Double, storageKey: String, defaultFraction: Double,
         @ViewBuilder first: () -> First, @ViewBuilder second: () -> Second) {
        self.axis = axis
        self.min0 = min0
        self.min1 = min1
        self.first = first()
        self.second = second()
        _fraction = AppStorage(wrappedValue: defaultFraction, storageKey)
    }

    var body: some View {
        GeometryReader { geo in
            let total = axis == .horizontal ? geo.size.width : geo.size.height
            let f = SplitLayout.clampFraction(fraction, total: total, min0: min0, min1: min1,
                                              divider: handleThickness)
            let firstLen = SplitLayout.firstLength(fraction: f, total: total, divider: handleThickness)
            Group {
                if axis == .horizontal {
                    HStack(spacing: 0) {
                        first.frame(width: firstLen, maxHeight: .infinity)
                        handle(total: total, current: f)
                        second.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        first.frame(height: firstLen, maxWidth: .infinity)
                        handle(total: total, current: f)
                        second.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func handle(total: Double, current: Double) -> some View {
        let isH = axis == .horizontal
        ZStack {
            Rectangle().fill(.clear)
            Capsule().fill(.secondary.opacity(0.35))
                .frame(width: isH ? 2 : 28, height: isH ? 28 : 2)
        }
        .frame(width: isH ? handleThickness : nil, height: isH ? nil : handleThickness)
        .frame(maxWidth: isH ? nil : .infinity, maxHeight: isH ? .infinity : nil)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { (isH ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() }
            else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let usable = max(total - handleThickness, 1)
                    if dragStartFraction == nil { dragStartFraction = current }
                    let startLen = (dragStartFraction ?? current) * usable
                    let delta = isH ? value.translation.width : value.translation.height
                    fraction = SplitLayout.clampFraction((startLen + delta) / usable,
                                                         total: total, min0: min0, min1: min1,
                                                         divider: handleThickness)
                }
                .onEnded { _ in dragStartFraction = nil }
        )
    }
}
```

- [ ] **Step 2: Regenerate the project (new app-target file) and build**

Run: `make gen && make build-mac`
Expected: `** BUILD SUCCEEDED **` (the view is unused so far — it must still compile cleanly).

- [ ] **Step 3: Commit**

```bash
git add Apps/INMeetings/INMeetings/Dashboard/ResizableSplit.swift Apps/INMeetings/INMeetings.xcodeproj
git commit -m "feat(app): ResizableSplit — reusable Liquid Glass drag splitter with persisted sizes"
```

---

### Task 3: Recompose `MeetingDetailView` into the split layout

**Files:**
- Modify: `Apps/INMeetings/INMeetings/Dashboard/MeetingDetailView.swift` (full replacement of the file below)

- [ ] **Step 1: Replace the file contents**

Overwrite `Apps/INMeetings/INMeetings/Dashboard/MeetingDetailView.swift` with:

```swift
// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome; side-by-side resizable panes.

import SwiftUI
import AVKit
import AppKit
import INMeetingsCore

struct MeetingDetailView: View {
    let meeting: MeetingRecord
    let store: RecordingStore
    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var observer: Any?
    @State private var isVideo = false
    @State private var isEditingCompany = false
    @State private var draftCompany = ""
    @State private var renamingSpeakerId: String?
    @State private var customName = ""
    @AppStorage("showSummaryPane") private var showSummaryPane = true
    private var pkg: TranscriptPackage? { store.transcript(for: meeting) }

    var body: some View {
        VStack(spacing: 0) {
            header; Divider()
            bodyArea.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !isVideo, player != nil { Divider(); playbackBar }
        }
        .onAppear(perform: configure).onDisappear(perform: teardown)
        .alert("Name this speaker", isPresented: Binding(
            get: { renamingSpeakerId != nil }, set: { if !$0 { renamingSpeakerId = nil } })) {
            TextField("Name", text: $customName)
            Button("Save") {
                if let id = renamingSpeakerId { store.renameSpeaker(customName, email: nil, speakerId: id, for: meeting) }
                renamingSpeakerId = nil
            }
            Button("Cancel", role: .cancel) { renamingSpeakerId = nil }
        }
    }

    /// The split-pane body: a left context column (video + summary) beside the transcript. Collapses to
    /// Summary | Transcript when there is no video, or to a full-width transcript when there is no context
    /// (no video and the summary is hidden or empty) — so no dead pane is ever left behind.
    @ViewBuilder private var bodyArea: some View {
        let showSummary = showSummaryPane && summaryHasContent
        if isVideo {
            ResizableSplit(axis: .horizontal, min0: 240, min1: 320,
                           storageKey: "detail.columnSplit", defaultFraction: 0.38) {
                if showSummary {
                    ResizableSplit(axis: .vertical, min0: 120, min1: 80,
                                   storageKey: "detail.mediaSplit", defaultFraction: 0.55) {
                        videoPane
                    } second: {
                        summaryPane
                    }
                } else {
                    videoPane
                }
            } second: {
                transcriptColumn
            }
        } else if showSummary {
            ResizableSplit(axis: .horizontal, min0: 240, min1: 320,
                           storageKey: "detail.columnSplit", defaultFraction: 0.38) {
                summaryPane
            } second: {
                transcriptColumn
            }
        } else {
            transcriptColumn
        }
    }

    @ViewBuilder private var videoPane: some View {
        if let player {
            PlayerView(player: player).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    /// The right column: speaker chips (when there are utterances) above the transcript scroll.
    @ViewBuilder private var transcriptColumn: some View {
        VStack(spacing: 0) {
            if pkg?.utterances.isEmpty == false {
                speakerLegend.padding(.horizontal).padding(.vertical, 6)
                Divider()
            }
            transcriptArea.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// True when the summary pane has something to show (so the header toggle + the pane appear).
    private var summaryHasContent: Bool {
        switch meeting.summaryState ?? "" {
        case "running", "failed": return true
        case "done": return store.summaryText(for: meeting) != nil
        default: return meeting.status == "transcribed"
        }
    }

    /// A row of speaker chips above the transcript. Each chip is a menu to assign that diarized speaker a
    /// name — one-tap from the meeting's attendees, or a custom name — persisted to transcript.json. (We
    /// can't know which voice is which automatically; that needs voice-ID.)
    @ViewBuilder private var speakerLegend: some View {
        let speakers = pkg?.speakers ?? []
        let attendees = store.metadata(for: meeting)?.attendees ?? []
        HStack(spacing: 8) {
            Image(systemName: "person.2").font(.caption).foregroundStyle(.secondary)
            ForEach(speakers, id: \.id) { sp in
                Menu {
                    ForEach(Array(attendees.enumerated()), id: \.offset) { _, att in
                        Button(att.name) { store.renameSpeaker(att.name, email: att.email, speakerId: sp.id, for: meeting) }
                    }
                    if !attendees.isEmpty { Divider() }
                    Button("Custom name…") { customName = sp.name ?? ""; renamingSpeakerId = sp.id }
                    if sp.name != nil {
                        Button("Reset to “\(sp.id)”", role: .destructive) {
                            store.renameSpeaker(nil, email: nil, speakerId: sp.id, for: meeting)
                        }
                    }
                } label: {
                    Text(sp.name ?? sp.id).font(.caption.weight(.medium))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(sp.side == "internal" ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12),
                            in: Capsule())
            }
            Spacer()
        }
    }

    /// The post-meeting Claude summary (saventa-summary auto-trigger), as a pane that fills its space:
    /// spinner while running; the paste-ready note when done (Copy / Re-summarize); the error + Retry on
    /// failure; or a Summarize button for a transcribed meeting that hasn't been summarized.
    @ViewBuilder private var summaryPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch meeting.summaryState ?? "" {
            case "running":
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Generating summary…").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
            case "done":
                if let text = store.summaryText(for: meeting) {
                    HStack {
                        Label("Summary", systemImage: "sparkles").font(.headline)
                        Spacer()
                        Button { copySummary(text) } label: { Label("Copy", systemImage: "doc.on.doc") }
                            .buttonStyle(.glass).controlSize(.small)
                        Button { store.summarize(meeting) } label: {
                            Label("Re-summarize", systemImage: "arrow.clockwise")
                        }.buttonStyle(.glass).controlSize(.small)
                    }
                    ScrollView {
                        Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            case "failed":
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(meeting.summaryError ?? "Summary failed.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { store.summarize(meeting) }.buttonStyle(.glass).controlSize(.small)
                }
            default:
                if meeting.status == "transcribed" {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundStyle(.secondary)
                        Text("No summary yet.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button { store.summarize(meeting) } label: { Label("Summarize", systemImage: "sparkles") }
                            .buttonStyle(.glassProminent).controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                if isEditingCompany {
                    TextField("Add company", text: $draftCompany)
                        .textFieldStyle(.roundedBorder).font(.title2.weight(.semibold))
                        .frame(maxWidth: 280)
                        .onSubmit { commitCompany() }
                } else {
                    Button {
                        draftCompany = meeting.company ?? ""; isEditingCompany = true
                    } label: {
                        Text(meeting.company?.isEmpty == false ? meeting.company! : "Add company")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(meeting.company?.isEmpty == false ? .primary : .secondary)
                    }.buttonStyle(.plain)
                }
                Text("\(meeting.title ?? "Meeting") · \(durationString(meeting.durationSeconds))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if summaryHasContent {
                Button { showSummaryPane.toggle() } label: { Label("Summary", systemImage: "sparkles") }
                    .buttonStyle(.glass).tint(showSummaryPane ? Color.accentColor : nil)
                    .help(showSummaryPane ? "Hide summary" : "Show summary")
            }
            Button { copyTranscript() } label: { Label("Copy", systemImage: "doc.on.doc") }
                .buttonStyle(.glass)
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: meeting.folderPath)]) }
                label: { Label("Reveal", systemImage: "folder") }.buttonStyle(.glass)
        }.padding()
    }

    @ViewBuilder private var transcriptArea: some View {
        if let us = pkg?.utterances, !us.isEmpty {
            let speakers = Dictionary(uniqueKeysWithValues: (pkg?.speakers ?? []).map { ($0.id, $0) })
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(us.enumerated()), id: \.offset) { i, u in
                        TranscriptSegmentView(utterance: u, speaker: speakers[u.speakerId],
                                              isActive: currentTime >= u.start && currentTime < u.end,
                                              onTap: { seek(to: u.start) })
                    }
                }.padding()
                .environment(\.layoutDirection, pkg?.language == "he" ? .rightToLeft : .leftToRight)
            }
        } else if meeting.status == "failed" {
            ContentUnavailableView {
                Label("Transcription failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(meeting.pipelineError ?? "The pipeline did not finish. See pipeline.log for details.")
            } actions: {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: meeting.folderPath).appendingPathComponent("pipeline.log")])
                } label: { Label("Reveal pipeline.log", systemImage: "doc.text.magnifyingglass") }
                    .buttonStyle(.glass)
            }
        } else {
            ContentUnavailableView("No transcript yet", systemImage: "text.alignleft")
        }
    }

    @ViewBuilder private var playbackBar: some View {
        if let player {
            HStack {
                Button { player.timeControlStatus == .playing ? player.pause() : player.play() }
                    label: { Image(systemName: "play.fill") }.buttonStyle(.glassProminent)
                Slider(value: Binding(get: { currentTime }, set: { seek(to: $0) }),
                       in: 0...max(meeting.durationSeconds ?? 1, 1))
                Text(durationString(currentTime)).monospacedDigit().foregroundStyle(.secondary)
            }.padding()
        }
    }

    private func configure() {
        teardown()
        guard let url = store.playbackURL(for: meeting) else { return }
        isVideo = ["mp4", "mov"].contains(url.pathExtension.lowercased())
        let p = AVPlayer(url: url)
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) {
            currentTime = $0.seconds.isFinite ? $0.seconds : 0
        }
        player = p
    }
    private func teardown() { if let player, let observer { player.removeTimeObserver(observer) }
        observer = nil; player?.pause(); player = nil }
    private func seek(to s: Double) {
        player?.seek(to: CMTime(seconds: s, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = s
    }
    private func copyTranscript() {
        let text = (pkg?.utterances ?? []).map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    private func copySummary(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    private func commitCompany() {
        isEditingCompany = false
        store.setCompany(draftCompany, for: meeting)
    }
}

/// AVKit's AppKit player view wrapped for SwiftUI. We use this instead of SwiftUI's `VideoPlayer`: on this
/// macOS/SDK, realizing `VideoPlayer` aborts the Swift runtime while instantiating `_AVKit_SwiftUI` generic
/// metadata (observed: `getSuperclassMetadata` → `fatalError`, repro'd 3× on opening a video meeting).
/// `AVPlayerView` is a plain `NSView`, so wrapping it ourselves (like the Drive picker's WKWebView) avoids
/// that path entirely — and gives native transport controls for free.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}
```

- [ ] **Step 2: Build the app**

Run: `make build-mac`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the full Core suite (no regression from the relocation)**

Run: `swift test`
Expected: PASS (all Core tests, including the 8 new `SplitLayoutTests`).

- [ ] **Step 4: Commit**

```bash
git add Apps/INMeetings/INMeetings/Dashboard/MeetingDetailView.swift
git commit -m "feat(app): side-by-side resizable meeting detail (media | transcript) + collapsible summary"
```

---

### Task 4: Live verification, manual-test checklist, and docs

**Files:**
- Create: `docs/manual-tests-modular-layout.md`
- Modify: `HANDOFF.md`, `DECISIONS.md`

- [ ] **Step 1: Launch the app and verify behavior (acceptance — build-green is NOT acceptance for UI)**

Run: `make run-mac`

Verify, in order:
1. Open a **video** meeting → video sits in the left column, transcript fills the right at full height; the audio footer is absent (video has inline controls).
2. Drag the **column** divider (⇆) left/right and the **video/summary** divider (⇅) up/down → both panes resize; cursor changes over the handles.
3. Open an **audio-only** meeting → layout is **Summary | Transcript** with the audio playback bar as a full-width footer.
4. Click **Summary** in the header to hide it → the audio meeting reflows to a **full-width transcript** (no dead left column); on a video meeting it reflows to **video | transcript**. Click again to show.
5. **Quit and relaunch** the app, reopen a meeting → the divider sizes and the summary-visible state are **remembered**.
6. Confirm the Hebrew transcript still reads **right-to-left** inside its pane.

If any check fails, fix in the relevant file and re-run `make build-mac` + `make run-mac` before continuing.

- [ ] **Step 2: Write the manual-test checklist**

Create `docs/manual-tests-modular-layout.md`:

```markdown
# Manual tests — modular / resizable meeting layout

Run `make run-mac`, then:

1. **Video meeting** — open one. Video is in the left column; transcript fills the right; no audio footer.
2. **Resize** — drag the column divider (⇆) and the video/summary divider (⇅). Both panes resize; the
   cursor changes over each handle.
3. **Audio-only meeting** — open one. Layout is Summary | Transcript; the audio playback bar is a
   full-width footer.
4. **Collapse summary** — click "Summary" in the header. Audio meeting → full-width transcript (no dead
   pane); video meeting → video | transcript. Click again to restore.
5. **Persistence** — quit, relaunch, reopen a meeting: divider sizes + summary visibility are remembered.
6. **RTL** — the Hebrew transcript still reads right-to-left inside its pane.
```

- [ ] **Step 3: Update `HANDOFF.md` and `DECISIONS.md`**

In `HANDOFF.md`, replace the "NEXT — START HERE: feature #2" pointer with a short "DONE this session" entry for the modular layout (branch `feat/modular-meeting-layout`, the new files, live-verified) and set the next pointer to the remaining v1 gaps (Ship phase + global cache-size cap). In `DECISIONS.md`, append a `### 2026-06-23 — Modular / resizable meeting detail layout` entry: side-by-side context|transcript via a custom `ResizableSplit` (over SwiftUI `HSplitView`/`VSplitView`, for persistence + glass), global `@AppStorage` divider fractions, collapsible summary, `SplitLayout` clamp math in Core. (Append-only — newest last.)

- [ ] **Step 4: Commit**

```bash
git add docs/manual-tests-modular-layout.md HANDOFF.md DECISIONS.md
git commit -m "docs: modular layout manual-test checklist + HANDOFF/DECISIONS"
```

---

## Self-Review

**Spec coverage:**
- Side-by-side context|transcript → Task 3 `bodyArea`. ✓
- Adapts to Summary|Transcript (no video) and full-width transcript (no context) → Task 3 `bodyArea` branches. ✓
- Collapsible summary via header toggle (`showSummaryPane`, default on) → Task 3 header + `summaryHasContent`. ✓
- Audio footer for audio-only → Task 3 `body` (`if !isVideo, player != nil`). ✓
- Speaker chips relocate to transcript column → Task 3 `transcriptColumn`. ✓
- Custom `ResizableSplit` over `HSplitView`/`VSplitView`, glass handle, persisted fraction → Task 2. ✓
- `SplitLayout` pure clamp math in Core, unit-tested → Task 1. ✓
- Global `@AppStorage` keys (`detail.columnSplit`, `detail.mediaSplit`, `showSummaryPane`) + defaults/mins → Tasks 2 & 3 (0.38 / 0.55 defaults; mins 240/320/120/80). ✓
- LTR chrome / RTL transcript content preserved → Task 3 `transcriptArea` keeps the scoped `.environment(\.layoutDirection,…)`. ✓
- Testing: Core unit tests + build + live run → Tasks 1, 2/3, 4. ✓

**Placeholder scan:** No TBD/TODO; all code blocks complete; the only "describe, don't show" step is the HANDOFF/DECISIONS prose edit (Task 4 Step 3), which is documentation, not code.

**Type consistency:** `SplitLayout.clampFraction(_:total:min0:min1:divider:)` and `SplitLayout.firstLength(fraction:total:divider:)` are used with identical signatures in Tasks 1 and 2. `ResizableSplit(axis:min0:min1:storageKey:defaultFraction:first:second:)` is used in Task 3 exactly as defined in Task 2. `summaryPane` / `summaryHasContent` / `transcriptColumn` / `videoPane` are defined and referenced consistently in Task 3.
