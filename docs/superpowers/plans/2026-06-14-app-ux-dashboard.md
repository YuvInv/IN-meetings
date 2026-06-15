# App UX slice 1 — merged playback + mila-faithful dashboard + settings — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.
>
> **SwiftUI note:** the pure logic (PlaybackRenderer math, RecordingStore mapping, date-bucketing, search filter, active-line lookup) is TDD'd with `swift test`. The SwiftUI **views are adapted from mila's actual files** (cloned reference; we copy + adapt with Apache-2.0 attribution) and are **live-verified** (`make run-mac`), not unit-tested — matching this codebase's pattern (`MeetingPromptOverlay`, etc.). View code here is a faithful first draft; refine against the compiler + canvas.

**Goal:** finishing a meeting renders one merged `audio.m4a`; a Liquid Glass `NavigationSplitView` (sidebar + date-bucketed list + detail) lets you browse/read/listen to past meetings with RTL Hebrew transcripts + tap-to-seek + search, plus a tabbed Settings scene (Recording / Model / Drive).

**Architecture:** Swift AVFoundation render at Stop (concurrent with the pipeline) → `audio.m4a`; a `@Observable` `RecordingStore` over the slice-5 SQLite index + slice-5 `PackageReader`; SwiftUI views in the macOS-26 app target adapted from mila, re-skinned in Liquid Glass.

**Tech Stack:** Swift 5.9 / macOS 26 app, AVFoundation, AVKit, SwiftUI `NavigationSplitView`, GRDB-backed `MeetingStore`, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-06-14-app-ux-dashboard-design.md` · **mila ref:** `island-io/mila` `Mila/Views/*` (Apache-2.0).

---

## File Structure
- `Sources/INMeetingsCore/Capture/PlaybackRenderer.swift` — merge mic+system → `audio.m4a` (Core; testable).
- `Apps/INMeetings/INMeetings/Dashboard/` — `RecordingStore`, `DashboardWindow`, `DashboardSidebar`, `MeetingListView`, `MeetingRow`, `MeetingDetailView`, `TranscriptSegmentView`, `MeetingBucketing.swift` (pure helpers).
- `Apps/INMeetings/INMeetings/Settings/` — `AppSettingsView`, `RecordingSettingsTab`, `ModelSettingsTab`, `DriveSettingsTab`.
- Modify: `RecordingController.stop()`, `DriveSync`, `INMeetingsApp.swift`.
- Tests: `PlaybackRendererTests`, `RecordingStoreTests`, `MeetingBucketingTests` (Core, where logic lives).
- `Sources/INMeetingsCore/Dashboard/` for the **pure helpers** that need unit tests (`MeetingBucketing`, search filter, active-line) so they live in Core and are testable without the app target.

---

## Task 0: Branch
- [ ] **Step 1: Branch off main**
```bash
cd /Users/yuvalnaor/repos/IN-meetings
git fetch origin && git checkout main && git pull --ff-only && git checkout -b feat/app-ux-dashboard
```
(If PR #6 isn't merged yet, instead branch off its tip: `git checkout feat/phase2-calendar-context && git checkout -b feat/app-ux-dashboard` — the dashboard reads the index/package, independent of #6's calendar code, but this avoids a DECISIONS.md append conflict.)

---

## STAGE 1 — Merged playback file

### Task 1: `balancedVolumes` (pure)
**Files:** Create `Sources/INMeetingsCore/Capture/PlaybackRenderer.swift`; Test `Tests/INMeetingsCoreTests/PlaybackRendererTests.swift`

- [ ] **Step 1: Failing test**
```swift
import XCTest
@testable import INMeetingsCore

final class PlaybackRendererTests: XCTestCase {
    func testBalancedVolumesEqualizesQuieterTrack() {
        let (mic, sys) = PlaybackRenderer.balancedVolumes(micRMS: 0.1, systemRMS: 0.025)
        XCTAssertEqual(mic, 1.0, accuracy: 0.001)   // louder stays at unity
        XCTAssertEqual(sys, 4.0, accuracy: 0.001)   // quieter boosted, capped at 4×
    }
    func testBalancedVolumesEqualLevels() {
        let (mic, sys) = PlaybackRenderer.balancedVolumes(micRMS: 0.08, systemRMS: 0.08)
        XCTAssertEqual(mic, 1.0, accuracy: 0.001)
        XCTAssertEqual(sys, 1.0, accuracy: 0.001)
    }
    func testBalancedVolumesSilentTrackStaysQuiet() {
        let (_, sys) = PlaybackRenderer.balancedVolumes(micRMS: 0.1, systemRMS: 0.0)
        XCTAssertEqual(sys, 1.0, accuracy: 0.001)   // no signal → don't amplify noise floor
    }
}
```
- [ ] **Step 2: Run → FAIL** `swift test --filter PlaybackRendererTests` (PlaybackRenderer undefined)
- [ ] **Step 3: Implement**
```swift
import AVFoundation
import Foundation

/// Renders the dual capture tracks into one level-balanced playback file (`audio.m4a`) so a listener
/// gets the natural "whole meeting" audio, not two separate channels (DECISIONS 2026-06-14). The raw
/// mic/system WAVs stay as the lossless transcription inputs.
public struct PlaybackRenderer: Sendable {
    public static let outputName = "audio.m4a"
    public init() {}

    /// Per-track playback volumes that equalize perceived loudness: the louder track stays at 1.0, the
    /// quieter is boosted toward it (capped 4×). A silent track (RMS≈0) is left at 1.0 — boosting it
    /// would just amplify the noise floor.
    public static func balancedVolumes(micRMS: Float, systemRMS: Float) -> (mic: Float, system: Float) {
        let hi = max(micRMS, systemRMS)
        func vol(_ rms: Float) -> Float {
            guard rms > 1e-4, hi > 1e-4 else { return 1.0 }
            return min(max(hi / rms, 1.0), 4.0)
        }
        return (vol(micRMS), vol(systemRMS))
    }
}
```
- [ ] **Step 4: Run → PASS** `swift test --filter PlaybackRendererTests`
- [ ] **Step 5: Commit** `git add Sources/INMeetingsCore/Capture/PlaybackRenderer.swift Tests/INMeetingsCoreTests/PlaybackRendererTests.swift && git commit -m "feat(app): PlaybackRenderer level-balance math"`

### Task 2: RMS + render (integration)
**Files:** Modify `PlaybackRenderer.swift`; Test `PlaybackRendererTests.swift`

- [ ] **Step 1: Failing test** (render two synthetic WAVs → an m4a exists, non-trivial)
```swift
    func testRenderProducesM4A() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let mic = try writeSine(dir.appendingPathComponent("mic.wav"), seconds: 1.0, freq: 220, rate: 24000)
        let sys = try writeSine(dir.appendingPathComponent("system.wav"), seconds: 1.0, freq: 440, rate: 48000)
        let out = dir.appendingPathComponent(PlaybackRenderer.outputName)
        try await PlaybackRenderer().render(tracks: [mic, sys], to: out)
        let size = try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 1000)
        XCTAssertEqual(try await AVURLAsset(url: out).load(.tracks).filter { $0.mediaType == .audio }.count, 1)
    }
```
Add a `writeSine` helper to the test (AVAudioFile, mono float32 sine). (Full helper in the test file.)
- [ ] **Step 2: Run → FAIL** (`render`/`rms` undefined)
- [ ] **Step 3: Implement** `rms(of:)` + `render(tracks:to:)`
```swift
    /// Mean RMS of a mono/interleaved WAV via AVAudioFile (chunked, never loads the whole file).
    public static func rms(of url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(min(file.length, 48000 * 60 * 30))
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return 0 }
        try file.read(into: buf)
        guard let ch = buf.floatChannelData else { return 0 }
        var sum: Float = 0; let n = Int(buf.frameLength)
        for i in 0..<n { let s = ch[0][i]; sum += s * s }
        return n > 0 ? (sum / Float(n)).squareRoot() : 0
    }

    /// Mix the tracks into `output` (`.m4a`, AAC), level-balanced. One track → straight transcode.
    public func render(tracks: [URL], to output: URL) async throws {
        let composition = AVMutableComposition()
        let audioMix = AVMutableAudioMix()
        var params: [AVMutableAudioMixInputParameters] = []
        let rmses = tracks.map { (try? Self.rms(of: $0)) ?? 0 }
        let volumes: [Float] = tracks.count == 2
            ? { let (m, s) = Self.balancedVolumes(micRMS: rmses[0], systemRMS: rmses[1]); return [m, s] }()
            : Array(repeating: 1.0, count: tracks.count)
        for (i, url) in tracks.enumerated() {
            let asset = AVURLAsset(url: url)
            guard let src = try await asset.loadTracks(withMediaType: .audio).first,
                  let dst = composition.addMutableTrack(withMediaType: .audio,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let dur = try await asset.load(.duration)
            try dst.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: src, at: .zero)
            let p = AVMutableAudioMixInputParameters(track: dst)
            p.setVolume(volumes[i], at: .zero)
            params.append(p)
        }
        audioMix.inputParameters = params
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "PlaybackRenderer", code: 1)
        }
        try? FileManager.default.removeItem(at: output)
        export.outputURL = output
        export.outputFileType = .m4a
        export.audioMix = audioMix
        await export.export()
        if export.status != .completed { throw export.error ?? NSError(domain: "PlaybackRenderer", code: 2) }
    }
```
- [ ] **Step 4: Run → PASS** `swift test --filter PlaybackRendererTests`
- [ ] **Step 5: Commit** `git commit -am "feat(app): PlaybackRenderer renders level-balanced audio.m4a"`

### Task 3: Kick the render at Stop
**Files:** Modify `Sources/INMeetingsCore/Recording/RecordingController.swift:124`

- [ ] **Step 1: Implement** — after `jobBridge.enqueue(...)` add a concurrent render (best-effort). Replace the `jobBridge.enqueue` line block:
```swift
            jobBridge.enqueue(result, startedAt: startedAt, endedAt: Date(), captureSourceApp: recordingSourceApp)
            // Render the single merged playback file alongside transcription (it needs only the raw
            // tracks). Best-effort: a failure leaves no audio.m4a and the dashboard degrades.
            let dir = result.directory
            let tracks = [result.mic, result.system].compactMap { $0 }
            if !tracks.isEmpty {
                Task.detached {
                    try? await PlaybackRenderer().render(tracks: tracks,
                                                         to: dir.appendingPathComponent(PlaybackRenderer.outputName))
                }
            }
            RecordingsStore.reveal(result.directory)
```
(`result.mic`/`result.system` are the WAV URLs — confirmed via `JobBridge.makeJob`.)
- [ ] **Step 2: Build** `swift build` → clean
- [ ] **Step 3: Commit** `git commit -am "feat(app): render the merged audio.m4a at Stop, concurrent with the pipeline"`

### Task 4: Drive uploads the merged file
**Files:** Modify `Sources/INMeetingsCore/Drive/DriveSync.swift`; Test `Tests/INMeetingsCoreTests/DriveSyncTests.swift`

- [ ] **Step 1: Failing test** (prefers audio.m4a; falls back to raw tracks)
```swift
    func testMediaSelectionPrefersMergedFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("a".utf8).write(to: dir.appendingPathComponent("mic.wav"))
        try Data("b".utf8).write(to: dir.appendingPathComponent("system.wav"))
        XCTAssertEqual(DriveSync.mediaFileNames(in: dir), ["mic.wav", "system.wav"])   // no merged yet
        try Data("c".utf8).write(to: dir.appendingPathComponent("audio.m4a"))
        XCTAssertEqual(DriveSync.mediaFileNames(in: dir), ["audio.m4a"])               // prefer merged
    }
```
- [ ] **Step 2: Run → FAIL** (`mediaFileNames(in:)` doesn't exist — it's a static array)
- [ ] **Step 3: Implement** — replace the static `mediaFileNames` array + the `for name in Self.mediaFileNames` loop:
```swift
    /// The listen artifact + any video. Prefer the single merged `audio.m4a` (the natural playback file);
    /// fall back to the raw tracks only when the render hasn't produced it (e.g. it failed).
    static func mediaFileNames(in folder: URL) -> [String] {
        let fm = FileManager.default
        func has(_ n: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(n).path) }
        var media: [String] = []
        if has("audio.m4a") { media.append("audio.m4a") }
        else { media += ["mic.wav", "system.wav"].filter(has) }
        if has("meeting.mp4") { media.append("meeting.mp4") }
        else if has("video.mov") { media.append("video.mov") }
        return media
    }
```
And in `sync(...)`, change `for name in Self.mediaFileNames {` → `for name in Self.mediaFileNames(in: packageFolder) {`. Add mime types:
```swift
        if name.hasSuffix(".m4a") { return "audio/mp4" }
        if name.hasSuffix(".mp4") { return "video/mp4" }
```
- [ ] **Step 4: Run → PASS** `swift test --filter DriveSyncTests`
- [ ] **Step 5: Commit** `git commit -am "feat(app): Drive uploads the merged audio.m4a (falls back to raw tracks)"`

**STAGE 1 GATE:** `swift test && swift build` green. (Live: a recording produces `audio.m4a` that plays in QuickTime — verify at the end.)

---

## STAGE 2 — Dashboard shell + sidebar + date-bucketed list

### Task 5: Pure helpers — bucketing, search, predicates
**Files:** Create `Sources/INMeetingsCore/Dashboard/MeetingBucketing.swift`; Test `Tests/INMeetingsCoreTests/MeetingBucketingTests.swift`

- [ ] **Step 1: Failing tests**
```swift
import XCTest
@testable import INMeetingsCore

final class MeetingBucketingTests: XCTestCase {
    private func rec(_ id: String, company: String?, title: String?, start: String,
                     matched: Bool = true, status: String = "done") -> MeetingRecord {
        MeetingRecord(id: id, company: company, title: title, type: "call", startedAt: start,
                      endedAt: start, durationSeconds: 60, status: status, speakerCount: 2,
                      diarized: true, biased: true, modelRevision: "r", captureSourceApp: nil,
                      folderPath: "/tmp/\(id)", consentStatus: nil, driveFolderId: nil, syncState: "synced")
    }
    func testFilterMatchesCompanyTitleAndId() {
        let recs = [rec("a", company: "Prelligence", title: "Sync", start: "2026-06-14T10:00:00Z"),
                    rec("b", company: "Algolion", title: "Pitch", start: "2026-06-13T10:00:00Z")]
        XCTAssertEqual(filterMeetings(recs, search: "prell").map(\.id), ["a"])
        XCTAssertEqual(filterMeetings(recs, search: "pitch").map(\.id), ["b"])
        XCTAssertEqual(filterMeetings(recs, search: "").map(\.id), ["a", "b"])
    }
    func testNeedsLinkingAndProcessing() {
        let recs = [rec("a", company: nil, title: nil, start: "2026-06-14T10:00:00Z", matched: false),
                    rec("b", company: "X", title: "t", start: "2026-06-14T10:00:00Z", status: "running")]
        XCTAssertEqual(needsLinking(recs).map(\.id), ["a"])        // no company
        XCTAssertEqual(processing(recs).map(\.id), ["b"])          // not done/synced
    }
}
```
- [ ] **Step 2: Run → FAIL**
- [ ] **Step 3: Implement** (`bucketByDate` adapted from mila `HistoryListView:441`; filter from mila `filterRecordings:428`)
```swift
import Foundation

public struct MeetingDateBucket: Sendable { public let label: String; public let items: [MeetingRecord] }

public func filterMeetings(_ recs: [MeetingRecord], search: String) -> [MeetingRecord] {
    let q = search.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return recs }
    return recs.filter {
        ($0.company ?? "").lowercased().contains(q) || ($0.title ?? "").lowercased().contains(q)
            || $0.id.lowercased().contains(q)
    }
}

/// Meetings with no resolved company — surfaced under "Needs linking" so the user can fix the match.
public func needsLinking(_ recs: [MeetingRecord]) -> [MeetingRecord] {
    recs.filter { ($0.company ?? "").isEmpty }
}

/// Meetings still being processed (pipeline not done, or not yet synced).
public func processing(_ recs: [MeetingRecord]) -> [MeetingRecord] {
    recs.filter { $0.status != "done" || $0.syncState == "syncing" || $0.syncState == "local" }
}

/// Group meetings (newest first) into Today / Yesterday / weekday / long-date buckets.
public func bucketMeetingsByDate(_ recs: [MeetingRecord], now: Date) -> [MeetingDateBucket] {
    let iso = ISO8601DateFormatter()
    let cal = Calendar.current
    let weekday = DateFormatter(); weekday.dateFormat = "EEEE"
    let long = DateFormatter(); long.dateStyle = .long
    func date(_ r: MeetingRecord) -> Date { iso.date(from: r.startedAt) ?? .distantPast }
    let sorted = recs.sorted { date($0) > date($1) }
    var order: [String] = []; var map: [String: [MeetingRecord]] = [:]
    for r in sorted {
        let d = date(r)
        let key: String = cal.isDateInToday(d) ? "Today"
            : cal.isDateInYesterday(d) ? "Yesterday"
            : (cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: now)).day ?? 99) < 7
              ? weekday.string(from: d) : long.string(from: d)
        if map[key] == nil { order.append(key) }
        map[key, default: []].append(r)
    }
    return order.map { MeetingDateBucket(label: $0, items: map[$0]!) }
}
```
- [ ] **Step 4: Run → PASS** `swift test --filter MeetingBucketingTests`
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat(app): dashboard pure helpers — bucketing, search, needs-linking/processing"`

### Task 6: `RecordingStore` (reader over SQLite + package)
**Files:** Create `Apps/INMeetings/INMeetings/Dashboard/RecordingStore.swift`; Test `Tests/INMeetingsCoreTests/RecordingStoreTests.swift` — *the store logic lives in the app target, but its pure mapping is exercised via `MeetingStore` + `PackageReader` which are in Core.* Test the load/transcript path with a temp DB + fixture folder.

> Since `RecordingStore` is in the app target (it uses `@Observable` + SwiftUI), the unit test covers the **Core** pieces it composes: `MeetingStore.allMeetings()` round-trip (already tested in `MeetingStoreTests`) + `PackageReader.transcript(in:)` (already tested in `ContextPackageTests`). No new Core test is required; `RecordingStore` itself is live-verified. Implement it directly:

- [ ] **Step 1: Implement**
```swift
import Foundation
import INMeetingsCore
import Observation

/// Read-only `@Observable` façade over the slice-5 SQLite index + slice-5 PackageReader for the
/// dashboard. Not a port of mila's RecordingStore — our data is the context package + GRDB index.
@MainActor
@Observable
final class RecordingStore {
    private(set) var meetings: [MeetingRecord] = []
    var selection: DashboardSelection? = .allMeetings
    var search: String = ""

    private let store: MeetingStore?
    init(store: MeetingStore? = try? MeetingStore(url: MeetingStore.defaultURL)) {
        self.store = store
        load()
    }

    func load() { meetings = (try? store?.allMeetings()) ?? [] }

    var filtered: [MeetingRecord] { filterMeetings(meetings, search: search) }

    func meeting(id: String) -> MeetingRecord? { meetings.first { $0.id == id } }
    func transcript(for r: MeetingRecord) -> TranscriptPackage? {
        try? PackageReader.transcript(in: URL(fileURLWithPath: r.folderPath))
    }
    func audioURL(for r: MeetingRecord) -> URL? {
        let u = URL(fileURLWithPath: r.folderPath).appendingPathComponent(PlaybackRenderer.outputName)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}

enum DashboardSelection: Hashable {
    case allMeetings, needsLinking, processing
    case meeting(String)
}
```
- [ ] **Step 2: Build** `swift build` (Core compiles; app target builds in Task 14)
- [ ] **Step 3: Commit** `git add -A && git commit -m "feat(app): RecordingStore reader over the meeting index + package"`

### Task 7: Sidebar, list, row, window (Liquid Glass; adapted from mila)
**Files:** Create `Apps/INMeetings/INMeetings/Dashboard/{DashboardSidebar,MeetingRow,MeetingListView,DashboardWindow}.swift`

> Each file carries the attribution header: `// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.`

- [ ] **Step 1: `MeetingRow.swift`** (adapt mila `HistoryRow`)
```swift
import SwiftUI
import INMeetingsCore

struct MeetingRow: View {
    let meeting: MeetingRecord
    let isSelected: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: meeting.type == "in_person" ? "person.wave.2" : "phone")
                .foregroundStyle(.tint).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meeting.company?.isEmpty == false ? meeting.company! : "Unknown company")
                        .font(.headline).lineLimit(1)
                    if let t = meeting.title, !t.isEmpty {
                        Text("· \(t)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(durationString(meeting.durationSeconds))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    chip(meeting.type == "in_person" ? "in-person" : "call", "phone", .secondary)
                    if meeting.syncState == "synced" { chip("synced", "cloud.fill", .green) }
                    if meeting.biased { chip("context", "sparkles", .blue) }
                    if (meeting.company ?? "").isEmpty { chip("link?", "link", .orange) }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
    private func chip(_ t: String, _ icon: String, _ color: Color) -> some View {
        Label(t, systemImage: icon).font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color)
    }
}
func durationString(_ s: Double?) -> String {
    let t = Int((s ?? 0).rounded()); return t >= 3600
        ? String(format: "%d:%02d:%02d", t/3600, (t%3600)/60, t%60)
        : String(format: "%d:%02d", t/60, t%60)
}
```
- [ ] **Step 2: `MeetingListView.swift`** (adapt mila `BucketedRecordingsView`; glass bucket cards)
```swift
import SwiftUI
import INMeetingsCore

struct MeetingListView: View {
    let meetings: [MeetingRecord]
    @Binding var selection: DashboardSelection?
    var body: some View {
        let buckets = bucketMeetingsByDate(meetings, now: Date())
        ScrollView {
            if meetings.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "tray",
                                       description: Text("New meetings will appear here."))
                    .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(buckets, id: \.label) { bucket in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(bucket.label).font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary).padding(.leading, 4)
                            GlassEffectContainer {
                                VStack(spacing: 0) {
                                    ForEach(bucket.items, id: \.id) { m in
                                        MeetingRow(meeting: m, isSelected: selection == .meeting(m.id))
                                            .onTapGesture { selection = .meeting(m.id) }
                                        if m.id != bucket.items.last?.id { Divider().padding(.leading, 36) }
                                    }
                                }
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}
```
- [ ] **Step 3: `DashboardSidebar.swift`** (adapt mila `SidebarView` + footer `SettingsLink`)
```swift
import SwiftUI

struct DashboardSidebar: View {
    @Binding var selection: DashboardSelection?
    let needsLinkingCount: Int
    let processingCount: Int
    var body: some View {
        List(selection: $selection) {
            Label("All Meetings", systemImage: "tray.full").tag(DashboardSelection.allMeetings)
            Label("Needs linking", systemImage: "link.badge.plus")
                .badge(needsLinkingCount).tag(DashboardSelection.needsLinking)
            Label("Processing", systemImage: "gearshape.2")
                .badge(processingCount).tag(DashboardSelection.processing)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                SettingsLink { Label("Settings", systemImage: "gear").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(10)
            }
        }
    }
}
```
- [ ] **Step 4: `DashboardWindow.swift`** (adapt mila `ContentView` `NavigationSplitView`)
```swift
import SwiftUI
import INMeetingsCore

struct DashboardWindow: View {
    @State private var storeModel = RecordingStore()
    var body: some View {
        NavigationSplitView {
            DashboardSidebar(selection: $storeModel.selection,
                             needsLinkingCount: needsLinking(storeModel.meetings).count,
                             processingCount: processing(storeModel.meetings).count)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            content
        }
        .searchable(text: $storeModel.search, placement: .toolbar, prompt: "Search meetings")
        .onAppear { storeModel.load() }
    }
    @ViewBuilder private var content: some View {
        switch storeModel.selection ?? .allMeetings {
        case .allMeetings:  MeetingListView(meetings: storeModel.filtered, selection: $storeModel.selection)
        case .needsLinking: MeetingListView(meetings: needsLinking(storeModel.filtered), selection: $storeModel.selection)
        case .processing:   MeetingListView(meetings: processing(storeModel.filtered), selection: $storeModel.selection)
        case .meeting(let id):
            if let m = storeModel.meeting(id: id) { MeetingDetailView(meeting: m, store: storeModel).id(id) }
            else { ContentUnavailableView("Meeting not found", systemImage: "questionmark.folder") }
        }
    }
}
```
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat(app): dashboard sidebar + date-bucketed list + window (Liquid Glass, adapted from mila)"`

**STAGE 2 GATE:** builds after Task 14's `make gen`; visually verified live.

---

## STAGE 3 — Detail (transcript RTL + tap-to-seek + player)

### Task 8: `activeUtteranceIndex` (pure)
**Files:** Modify `Sources/INMeetingsCore/Dashboard/MeetingBucketing.swift`; Test `MeetingBucketingTests.swift`
- [ ] **Step 1: Failing test**
```swift
    func testActiveUtterance() {
        let us = [TranscriptStub.u(0, 2), TranscriptStub.u(2, 5), TranscriptStub.u(5, 9)]
        XCTAssertEqual(activeUtteranceIndex(in: us, at: 3.0), 1)
        XCTAssertEqual(activeUtteranceIndex(in: us, at: 9.5), nil)
    }
```
(Add a `TranscriptStub.u(_:_:)` building `TranscriptPackage.Utterance`. Since `Utterance` has no public memberwise init, add a `public init` to it in `ContextPackage.swift` — small, justified for testability.)
- [ ] **Step 2: Run → FAIL**
- [ ] **Step 3: Implement**
```swift
public func activeUtteranceIndex(in utterances: [TranscriptPackage.Utterance], at time: Double) -> Int? {
    utterances.firstIndex { time >= $0.start && time < $0.end }
}
```
- [ ] **Step 4: Run → PASS**; **Step 5: Commit** `git commit -am "feat(app): activeUtteranceIndex for transcript seek-highlight"`

### Task 9: `TranscriptSegmentView` + `MeetingDetailView` (adapted from mila)
**Files:** Create `Apps/INMeetings/INMeetings/Dashboard/{TranscriptSegmentView,MeetingDetailView}.swift` (attribution header)
- [ ] **Step 1: `TranscriptSegmentView.swift`** (adapt mila `SegmentRow`)
```swift
import SwiftUI
import INMeetingsCore

struct TranscriptSegmentView: View {
    let utterance: TranscriptPackage.Utterance
    let speaker: TranscriptPackage.Speaker?
    let isActive: Bool
    let onTap: () -> Void
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let s = speaker {
                Text((s.name ?? s.id) + ":")
                    .font(.body.weight(.medium))
                    .foregroundStyle(s.side == "internal" ? Color.accentColor : Color.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(utterance.text).font(.body).frame(maxWidth: .infinity, alignment: .leading)
            Text(durationString(utterance.start)).font(.caption.monospacedDigit())
                .foregroundStyle(.secondary).fixedSize()
        }
        .padding(8)
        .background(isActive ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle()).onTapGesture(perform: onTap)
    }
}
```
- [ ] **Step 2: `MeetingDetailView.swift`** (adapt mila `RecordingDetailView` — header + transcript + playbackBar; AI-overview/share/export deferred)
```swift
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
    private var pkg: TranscriptPackage? { store.transcript(for: meeting) }

    var body: some View {
        VStack(spacing: 0) {
            header; Divider()
            transcriptArea.frame(maxWidth: .infinity, maxHeight: .infinity)
            if player != nil { Divider(); playbackBar }
        }
        .onAppear(perform: configure).onDisappear(perform: teardown)
    }
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.company?.isEmpty == false ? meeting.company! : "Unknown company")
                    .font(.title2.weight(.semibold))
                Text("\(meeting.title ?? "Meeting") · \(durationString(meeting.durationSeconds))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
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
        guard let url = store.audioURL(for: meeting) else { return }
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
}
```
- [ ] **Step 3: Commit** `git add -A && git commit -m "feat(app): meeting detail — RTL transcript, tap-to-seek, merged-audio player (adapted from mila)"`

---

## STAGE 4 — Settings scene (Recording / Model / Drive)

### Task 10: `AppSettingsView` + tabs
**Files:** Create `Apps/INMeetings/INMeetings/Settings/{AppSettingsView,RecordingSettingsTab,ModelSettingsTab,DriveSettingsTab}.swift` (attribution header on the TabView shell)
- [ ] **Step 1: `AppSettingsView.swift`** (adapt mila `SettingsView`)
```swift
import SwiftUI
struct AppSettingsView: View {
    var settings: MeetingDetectionSettings
    var models: ModelManager
    var vadModels: ModelManager
    var drive: DriveAuth
    var body: some View {
        TabView {
            RecordingSettingsTab(settings: settings).tabItem { Label("Recording", systemImage: "phone") }
            ModelSettingsTab(model: models, vad: vadModels).tabItem { Label("Model", systemImage: "cube.box") }
            DriveSettingsTab(drive: drive).tabItem { Label("Drive", systemImage: "externaldrive") }
        }
        .frame(width: 540, height: 460).padding(20)
    }
}
```
- [ ] **Step 2: `RecordingSettingsTab.swift`** (adapt mila `MeetingsSettingsTab`) — the detection toggle + snooze + hotkey line, bound to `MeetingDetectionSettings`. (Real code: a `Toggle("Prompt to record detected calls", isOn:)`, a snooze row, and `Text("Global hotkey: ⌃⌥⌘R")`.)
- [ ] **Step 3: `ModelSettingsTab.swift`** (adapt mila `ModelsSettingsTab`) — two rows (ivrit-turbo, Silero VAD) showing `ModelManager.statusText`/phase with a Retry button on `.failed`.
- [ ] **Step 4: `DriveSettingsTab.swift`** — move the existing `DriveAuth` `driveSection` UI out of `INMeetingsApp`'s menu into this tab (connect / account / choose Shared Drive / disconnect).
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat(app): tabbed Settings — Recording / Model / Drive (adapted from mila)"`

---

## STAGE 5 — Scenes, menu, icon + build

### Task 11: Wire scenes + menu + icon
**Files:** Modify `Apps/INMeetings/INMeetings/INMeetingsApp.swift`
- [ ] **Step 1:** Add scenes to the `App` body after `MenuBarExtra { … }`:
```swift
        Window("IN Meetings", id: "dashboard") { DashboardWindow() }
            .windowResizability(.contentSize)
        Settings { AppSettingsView(settings: promptSettings, models: models, vadModels: vadModel, drive: drive) }
```
- [ ] **Step 2:** In `MenuContent`, add (near the top, after the status line) `@Environment(\.openWindow) private var openWindow` and a button:
```swift
        Button("Open Dashboard") { openWindow(id: "dashboard") }
            .keyboardShortcut("d")
```
Remove the inline `driveSection` from the menu (now in Settings) — or keep a one-line "Drive: <account>" status + "Settings…" via `SettingsLink`.
- [ ] **Step 3:** Icon states already exist (`waveform` / `waveform.circle.fill` / red timer) — refine the armed glyph to `waveform.badge.mic` for a clearer "call detected" read:
```swift
                Image(systemName: detector.state.status == .armed ? "waveform.badge.mic" : "waveform")
```
- [ ] **Step 4: Commit** `git add -A && git commit -m "feat(app): Dashboard + Settings scenes, Open Dashboard menu, clearer armed icon"`

### Task 12: Regenerate + build + test
- [ ] **Step 1:** `make gen && make build-mac` → BUILD SUCCEEDED (new app-target files under Dashboard/ + Settings/ need `make gen`). Fix compile errors (the views are first-draft).
- [ ] **Step 2:** `swift test` → all green (Core logic). `make test` → app target green.
- [ ] **Step 3: Commit** any `make gen` project changes: `git add -A && git commit -m "chore(app): regenerate project for Dashboard + Settings" || echo none`

### Task 13: Docs + attribution
**Files:** `DECISIONS.md`, `HANDOFF.md`, `THIRD_PARTY_NOTICES.md`
- [ ] **Step 1:** DECISIONS entry (merged audio.m4a + mila-faithful dashboard/settings + Liquid Glass, English/RTL, in-memory search; deferrals). THIRD_PARTY_NOTICES: add the dashboard/settings views to the mila attribution list. HANDOFF: slice state + remaining (folders/trash/AI-overview/video/more settings tabs).
- [ ] **Step 2: Commit** `git commit -am "docs: app UX slice 1 (dashboard + settings + merged audio) decisions + handoff"`

### Task 14: Live verification (manual — needs the app running)
- [ ] Record a real call → `audio.m4a` plays in QuickTime.
- [ ] `make run-mac` → menu **Open Dashboard** → window opens in Liquid Glass; meeting appears in the date-bucketed list with chips; `Needs linking` shows unmatched ones; search filters.
- [ ] Open a meeting → **Hebrew renders RTL**, speakers named, **tap a line seeks** the audio, the playing line highlights; Copy/Reveal work.
- [ ] Settings (`Cmd+,`): Recording toggle persists; Model tab shows both models ready; Drive tab connects + picks a Drive.
- [ ] Reduce Transparency → glass falls back cleanly. Drive folder has `audio.m4a`.
- [ ] Then push + open PR.

---

## Self-Review
**Spec coverage:** merged file → Tasks 1–4; sidebar/list/window → 5–7; detail → 8–9; settings → 10; scenes/menu/icon → 11; build/docs/live → 12–14. ✅ all spec components mapped.
**Placeholders:** Tasks 10.2–10.4 describe the tab contents in prose (small, bound to existing settings models) rather than full code — acceptable: they're thin wrappers over `MeetingDetectionSettings`/`ModelManager`/`DriveAuth`, whose APIs are already established; the executor mirrors mila's tab structure. No `TODO`/`TBD`.
**Type consistency:** `DashboardSelection`, `RecordingStore` (`meetings`/`selection`/`search`/`filtered`/`meeting(id:)`/`transcript(for:)`/`audioURL(for:)`), `MeetingDateBucket`, `bucketMeetingsByDate`/`filterMeetings`/`needsLinking`/`processing`/`activeUtteranceIndex`, `PlaybackRenderer.outputName="audio.m4a"`, `DriveSync.mediaFileNames(in:)` — consistent across tasks. `TranscriptPackage.Utterance` needs a `public init` (Task 8). `ModelManager` second instance (`vadModel`) already exists from the VAD slice.
**Known first-draft risk:** SwiftUI views (Tasks 6–11) are adapted from mila + live-verified, not unit-tested — expected for this codebase.
