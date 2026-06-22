# Calendar Upload + Context — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user pick a calendar event in a day-agenda panel, upload an audio/video recording, and have the event's attendees/company/time enrich a single-track transcription (with attendees offered as one-tap speaker labels).

**Architecture:** Logic lives in `INMeetingsCore` (SPM, auto-built, unit-testable): a day-agenda view model, an audio normalizer (→16 kHz mono WAV), a synthetic import-job builder, an import coordinator, plus `JobBridge.enqueueImport` and a `MeetingStore` migration. Only the SwiftUI inspector view + dashboard wiring live in the app target. The existing Python pipeline is reused unchanged — `profile: "inPerson"` already does single-track diarization, and a `context.input.json` pinned to one event already flows attendees/company/`calendarEventId` into `metadata.json`.

**Tech Stack:** Swift 6 / SwiftUI / Observation, GRDB (SQLite), AVFoundation (audio decode/resample), Google Calendar v3, Python pipeline (whisper.cpp + senko).

---

## Design decisions locked in (from the spec)

- **Speakers = assisted labeling.** Pipeline emits `Speaker 1…N`, `side="unknown"`; the assigned event's attendees become one-tap label candidates. The detail view **already** reads `store.metadata(for:)?.attendees` for its speaker-chip menu (`MeetingDetailView.swift:54-60`) → **no detail-view change needed**.
- **Single mixed track** → processed with `profile: "inPerson"` (the only profile that diarizes one track into N speakers). Consequence: `metadata.meeting.type` becomes `"in_person"` (set from profile in `metadata.py`). Provenance is carried by a **new `source` field** (`"live"`/`"imported"`), not by `type`.
- **Auto-summary stays call-only** (`JobBridge.indexCompletedPackage` gates on `type == "call"`). Imports (`in_person`) don't auto-summarize; the existing manual **Summarize** button still works. (No change in this plan.)
- **Event-preferred, no-event fallback.** No-event imports skip the pinned context → no attendees/company (set by hand).
- **`source` provenance lives in `job.json`** (Swift-written) and is read at index time — this avoids touching the frozen `metadata.json` schema (ADR-005). `calendarEventId` comes from `metadata.meeting.calendarEventId` (already in the schema).

## File structure

**INMeetingsCore (SPM — no `make gen`):**
- Modify `Sources/INMeetingsCore/Store/MeetingStore.swift` — migration v4 (`source`, `calendarEventId`); `MeetingRecord` fields; index population; two queries.
- Modify `Sources/INMeetingsCore/Calendar/CalendarClient.swift` — optional `maxResults` param.
- Modify `Sources/INMeetingsCore/Calendar/CalendarContext.swift` — `fetchEvents`, `writePinnedInput`, `CalendarEventsProviding` conformance.
- Create `Sources/INMeetingsCore/Calendar/CalendarEventsProviding.swift` — the protocol.
- Create `Sources/INMeetingsCore/Calendar/CalendarPanelModel.swift` — day-agenda `@Observable` view model.
- Create `Sources/INMeetingsCore/Import/ImportJob.swift` — pure synthetic-job builder.
- Create `Sources/INMeetingsCore/Import/AudioImporter.swift` — AVFoundation → 16 kHz mono WAV.
- Create `Sources/INMeetingsCore/Import/MeetingImporter.swift` — import coordinator (DI'd seams).
- Modify `Sources/INMeetingsCore/JobBridge/JobBridge.swift` — `enqueueImport(...)`.

**App target (`Apps/INMeetings` — new files need `make gen`):**
- Create `Apps/INMeetings/INMeetings/Calendar/CalendarPanel.swift` — the SwiftUI inspector.
- Modify `Apps/INMeetings/INMeetings/Dashboard/DashboardWindow.swift` — inspector toggle + `.fileImporter` wiring.
- Modify `Apps/INMeetings/INMeetings/Dashboard/RecordingStore.swift` — recorded-event-id + open-by-event passthroughs + an import entry point.

**Tests:**
- `Tests/INMeetingsCoreTests/` — MeetingStore migration/index, CalendarContext pinned input, ImportJob, AudioImporter, MeetingImporter, CalendarPanelModel.
- `pipeline/tests/test_import.py` — import-style job (single track + pinned 1-candidate context) → metadata.

---

## Task 1: MeetingStore — `source` + `calendarEventId` (migration v4, index, queries)

**Files:**
- Modify: `Sources/INMeetingsCore/Store/MeetingStore.swift`
- Test: `Tests/INMeetingsCoreTests/MeetingStoreImportTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/INMeetingsCoreTests/MeetingStoreImportTests.swift`:

```swift
import XCTest
import Foundation
@testable import INMeetingsCore

final class MeetingStoreImportTests: XCTestCase {
    /// Write a minimal valid context package into a temp folder; return the folder.
    private func writePackage(id: String, source: String?, eventId: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let eid = eventId.map { "\"calendar_event_id\":\"\($0)\"," } ?? ""
        let metadata = """
        {"schema_version":"1.0",
         "meeting":{\(eid)"start":"2026-06-22T10:00:00Z","end":"2026-06-22T10:30:00Z","type":"in_person"},
         "recording":{"tracks":["mic"],"video":false},
         "transcription":{"engine":"whisper.cpp","model_revision":"rev","language":"he","biased":false}}
        """
        try metadata.write(to: dir.appendingPathComponent("metadata.json"), atomically: true, encoding: .utf8)
        if let source {
            try "{\"source\":\"\(source)\"}".write(to: dir.appendingPathComponent("job.json"),
                                                  atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testIndexPopulatesSourceAndEventId() throws {
        let store = try MeetingStore()
        let folder = try writePackage(id: "imp-1", source: "imported", eventId: "evt123")
        let record = try store.indexPackage(at: folder)
        XCTAssertEqual(record.source, "imported")
        XCTAssertEqual(record.calendarEventId, "evt123")
    }

    func testIndexDefaultsToLiveWhenNoJobSource() throws {
        let store = try MeetingStore()
        let folder = try writePackage(id: "live-1", source: nil, eventId: nil)
        let record = try store.indexPackage(at: folder)
        XCTAssertEqual(record.source, "live")
        XCTAssertNil(record.calendarEventId)
    }

    func testRecordedEventIdQueries() throws {
        let store = try MeetingStore()
        _ = try store.indexPackage(at: writePackage(id: "imp-2", source: "imported", eventId: "evtA"))
        XCTAssertEqual(try store.calendarEventIdsWithRecording(), ["evtA"])
        XCTAssertEqual(try store.meeting(forCalendarEventId: "evtA")?.id, "imp-2")
        XCTAssertNil(try store.meeting(forCalendarEventId: "nope"))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter MeetingStoreImportTests`
Expected: FAIL — `value of type 'MeetingRecord' has no member 'source'` (compile error).

- [ ] **Step 3: Add the migration + fields + index population + queries**

In `MeetingStore.swift`, add migration v4 at the end of `migrator` (after `v3-summary-state`, before `return migrator`):

```swift
        migrator.registerMigration("v4-import-source") { db in
            // Provenance of an imported recording vs a live capture, and the calendar event it's bound to
            // (the latter also backfills live captures that matched an event, so the calendar panel can
            // mark events "✓ recorded"). `source` is NOT NULL with a "live" default so existing rows are
            // unambiguous; `calendarEventId` is nullable (no-event imports + unmatched live captures).
            try db.alter(table: MeetingRecord.databaseTableName) { t in
                t.add(column: "source", .text).notNull().defaults(to: "live")
                t.add(column: "calendarEventId", .text)
            }
        }
```

In `struct MeetingRecord`, add after `summarySessionId`:

```swift
    /// "live" (default) | "imported" — provenance, surfaced as the dashboard "Imported" badge.
    public var source: String = "live"
    /// The Google Calendar event id this meeting is bound to (nil = none). Lets the calendar panel mark
    /// events as already recorded and open them. Filled from `metadata.meeting.calendarEventId` at index.
    public var calendarEventId: String? = nil
```

In `indexPackage(at:)`, before constructing `record`, read the job source:

```swift
        let jobSource = (try? Data(contentsOf: folder.appendingPathComponent("job.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { $0["source"] as? String } ?? "live"
```

Add these two lines to the `MeetingRecord(...)` initializer in `indexPackage` (after `pipelineError: nil`):

```swift
            pipelineError: nil,   // a successful (re-)index clears any prior failure
            source: jobSource,
            calendarEventId: metadata.meeting.calendarEventId
```

(Change the existing `pipelineError: nil` line to end with a comma and append the two new args.)

In `markFailed(folder:error:)`, append to its `MeetingRecord(...)` initializer (after `pipelineError: ...`):

```swift
            pipelineError: error ?? "Transcription failed (see pipeline.log).",
            source: (job["source"] as? String) ?? existing?.source ?? "live",
            calendarEventId: existing?.calendarEventId
```

Add the two queries in the `// MARK: - Queries` section:

```swift
    /// The set of calendar event ids that already have a recording (any source). Powers the panel's
    /// "✓ recorded" marker. Distinct, non-null only.
    public func calendarEventIdsWithRecording() throws -> Set<String> {
        try dbQueue.read { db in
            Set(try String.fetchAll(db,
                sql: "SELECT DISTINCT calendarEventId FROM meeting WHERE calendarEventId IS NOT NULL"))
        }
    }

    /// The most recent meeting bound to a calendar event, if any (click-through from the panel).
    public func meeting(forCalendarEventId eventId: String) throws -> MeetingRecord? {
        try dbQueue.read { db in
            try MeetingRecord.filter(Column("calendarEventId") == eventId)
                .order(Column("startedAt").desc).fetchOne(db)
        }
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter MeetingStoreImportTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full core suite to confirm no regressions**

Run: `swift test`
Expected: PASS (all existing tests + the 3 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/INMeetingsCore/Store/MeetingStore.swift Tests/INMeetingsCoreTests/MeetingStoreImportTests.swift
git commit -m "feat(store): index source + calendarEventId for imports (migration v4)"
```

---

## Task 2: CalendarContext — `fetchEvents`, `writePinnedInput`, `CalendarEventsProviding`

**Files:**
- Modify: `Sources/INMeetingsCore/Calendar/CalendarClient.swift`
- Modify: `Sources/INMeetingsCore/Calendar/CalendarContext.swift`
- Create: `Sources/INMeetingsCore/Calendar/CalendarEventsProviding.swift`
- Test: `Tests/INMeetingsCoreTests/CalendarPinnedInputTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/INMeetingsCoreTests/CalendarPinnedInputTests.swift`:

```swift
import XCTest
import Foundation
@testable import INMeetingsCore

final class CalendarPinnedInputTests: XCTestCase {
    func testPinnedPayloadHasSingleCandidateWithAttendees() throws {
        let event = CalendarEvent(
            id: "evt123", summary: "Acme intro",
            start: .init(dateTime: "2026-06-22T10:00:00Z", date: nil),
            end: .init(dateTime: "2026-06-22T10:30:00Z", date: nil),
            hangoutLink: "https://meet.google.com/x",
            attendees: [.init(email: "dana@acme.com", displayName: "Dana Cohen", organizer: false)])
        let iso = ISO8601DateFormatter()
        let start = iso.date(from: "2026-06-22T10:00:00Z")!
        let end = iso.date(from: "2026-06-22T10:30:00Z")!

        let payload = CalendarContext.inputPayload(
            internalDomain: "in-venture.com", candidates: [event],
            captureSourceApp: nil, startedAt: start, endedAt: end)

        let candidates = try XCTUnwrap(payload["candidates"] as? [[String: Any]])
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0]["id"] as? String, "evt123")
        let attendees = try XCTUnwrap(candidates[0]["attendees"] as? [[String: Any]])
        XCTAssertEqual(attendees.first?["email"] as? String, "dana@acme.com")
        XCTAssertEqual(payload["status"] as? String, "ok")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter CalendarPinnedInputTests`
Expected: PASS already? No — `inputPayload` is currently `static` but **internal** (no access modifier). The test is in the same module via `@testable`, so it compiles. Run it: it should PASS immediately (this asserts existing behavior). If it PASSES, that's fine — it's the regression guard for the pinned path. Proceed to add the new API the coordinator needs (below), whose behavior is covered by Task 6's MeetingImporter test.

- [ ] **Step 3: Add `maxResults` to CalendarClient**

In `CalendarClient.swift`, change `eventsURL` and `fetchEvents` to accept `maxResults` (default keeps live behavior):

```swift
    static func eventsURL(timeMin: Date, timeMax: Date, maxResults: Int = 10) -> URL {
```
and within it change the query item:
```swift
            URLQueryItem(name: "maxResults", value: String(maxResults)),
```
and:
```swift
    public func fetchEvents(timeMin: Date, timeMax: Date, maxResults: Int = 10) async throws -> [CalendarEvent] {
        var request = URLRequest(url: Self.eventsURL(timeMin: timeMin, timeMax: timeMax, maxResults: maxResults))
```

- [ ] **Step 4: Add `fetchEvents` + `writePinnedInput` to CalendarContext**

In `CalendarContext.swift`, add these public methods (after `writeInput`):

```swift
    /// Fetch events overlapping `[timeMin, timeMax]` (the calendar panel's per-day query). Higher
    /// `maxResults` than the live candidate fetch since a full day can hold many events.
    public func fetchEvents(timeMin: Date, timeMax: Date) async throws -> [CalendarEvent] {
        try await client.fetchEvents(timeMin: timeMin, timeMax: timeMax, maxResults: 250)
    }

    /// Write `context.input.json` pinned to ONE chosen event (the import path): the Python assembler
    /// matches by window overlap, so we set the hint window to the event's own start/end → a 100% overlap
    /// makes it the unambiguous match. No network call (the event is already in hand). Best-effort.
    public func writePinnedInput(into directory: URL, event: CalendarEvent, startedAt: Date, endedAt: Date) {
        let domain = tokenStore.load().map { Self.domain(ofEmail: $0.account) } ?? ""
        let payload = Self.inputPayload(internalDomain: domain, candidates: [event],
                                        captureSourceApp: nil, startedAt: startedAt, endedAt: endedAt)
        try? Self.write(payload, into: directory)
    }
```

- [ ] **Step 5: Add the protocol + conformance**

Create `Sources/INMeetingsCore/Calendar/CalendarEventsProviding.swift`:

```swift
import Foundation

/// The slice of `CalendarContext` the day-agenda view model depends on — a seam so the model can be
/// unit-tested with a fake (no network, no Keychain).
public protocol CalendarEventsProviding: Sendable {
    var isConnected: Bool { get }
    func fetchEvents(timeMin: Date, timeMax: Date) async throws -> [CalendarEvent]
}

extension CalendarContext: CalendarEventsProviding {}
```

- [ ] **Step 6: Run tests + commit**

Run: `swift test --filter CalendarPinnedInputTests`
Expected: PASS.

```bash
git add Sources/INMeetingsCore/Calendar/
git add Tests/INMeetingsCoreTests/CalendarPinnedInputTests.swift
git commit -m "feat(calendar): per-day fetchEvents + event-pinned context input + provider protocol"
```

---

## Task 3: ImportJob — the synthetic single-track job builder

**Files:**
- Create: `Sources/INMeetingsCore/Import/ImportJob.swift`
- Test: `Tests/INMeetingsCoreTests/ImportJobTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/INMeetingsCoreTests/ImportJobTests.swift`:

```swift
import XCTest
import Foundation
@testable import INMeetingsCore

final class ImportJobTests: XCTestCase {
    func testMakeProducesInPersonSingleTrackImportJob() {
        let iso = ISO8601DateFormatter()
        let start = iso.date(from: "2026-06-22T10:00:00Z")!
        let end = iso.date(from: "2026-06-22T10:30:00Z")!
        let dir = URL(fileURLWithPath: "/tmp/IN Meetings/Recordings/2026-06-22_10-00-00")

        let job = ImportJob.make(meetingId: dir.lastPathComponent, directory: dir,
                                 audioFilename: "audio.wav", startedAt: start, endedAt: end)

        XCTAssertEqual(job["meeting_id"] as? String, "2026-06-22_10-00-00")
        XCTAssertEqual(job["directory"] as? String, dir.path)
        XCTAssertEqual(job["profile"] as? String, "inPerson")
        XCTAssertEqual(job["source"] as? String, "import")
        XCTAssertEqual(job["video"] as? Bool, false)
        XCTAssertEqual((job["tracks"] as? [String: String])?["mic"], "audio.wav")
        XCTAssertNil((job["tracks"] as? [String: String])?["system"])
        XCTAssertEqual(job["started_at"] as? String, iso.string(from: start))
        XCTAssertEqual(job["ended_at"] as? String, iso.string(from: end))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter ImportJobTests`
Expected: FAIL — `cannot find 'ImportJob' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/INMeetingsCore/Import/ImportJob.swift`:

```swift
import Foundation

/// Builds the synthetic `job.json` for an imported recording (ADR-009 contract, mirrored in `pipeline/
/// job.py`). An import is always a single mixed track → `profile: "inPerson"` (the only profile that
/// diarizes one track into N speakers) and `tracks.mic` points at the normalized WAV. The extra
/// `source: "import"` key is read back at index time (MeetingStore) for provenance; `Job.load` ignores
/// it. Kept pure for testability.
public enum ImportJob {
    public static func make(meetingId: String, directory: URL, audioFilename: String,
                            startedAt: Date, endedAt: Date) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        return [
            "meeting_id": meetingId,
            "directory": directory.path,
            "profile": "inPerson",
            "tracks": ["mic": audioFilename],
            "started_at": iso.string(from: startedAt),
            "ended_at": iso.string(from: endedAt),
            "created_at": iso.string(from: endedAt),
            "video": false,
            "source": "import",
        ]
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter ImportJobTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/INMeetingsCore/Import/ImportJob.swift Tests/INMeetingsCoreTests/ImportJobTests.swift
git commit -m "feat(import): synthetic single-track import job builder"
```

---

## Task 4: AudioImporter — normalize any file → 16 kHz mono WAV

**Files:**
- Create: `Sources/INMeetingsCore/Import/AudioImporter.swift`
- Test: `Tests/INMeetingsCoreTests/AudioImporterTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/INMeetingsCoreTests/AudioImporterTests.swift`:

```swift
import XCTest
import AVFoundation
@testable import INMeetingsCore

final class AudioImporterTests: XCTestCase {
    /// Synthesize a short stereo 48 kHz WAV tone we can feed to the importer.
    private func makeStereoWav(at url: URL, seconds: Double = 0.5) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(48000 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for ch in 0..<2 {
            let p = buffer.floatChannelData![ch]
            for i in 0..<Int(frames) { p[i] = sinf(2 * .pi * 440 * Float(i) / 48000) * 0.2 }
        }
        try file.write(from: buffer)
    }

    func testConvertsToSixteenKMono() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let src = tmp.appendingPathComponent("import-src-\(UUID().uuidString).wav")
        let out = tmp.appendingPathComponent("import-out-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: out) }
        try makeStereoWav(at: src)

        try await AudioImporter.convertToWav16kMono(src, to: out)

        let result = try AVAudioFile(forReading: out)
        XCTAssertEqual(result.fileFormat.sampleRate, 16000, accuracy: 0.5)
        XCTAssertEqual(result.fileFormat.channelCount, 1)
        XCTAssertGreaterThan(result.length, 0)
    }

    func testThrowsWhenNoAudioTrack() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let bogus = tmp.appendingPathComponent("not-audio-\(UUID().uuidString).wav")
        try Data([0x00, 0x01, 0x02]).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }
        do {
            try await AudioImporter.convertToWav16kMono(bogus, to: tmp.appendingPathComponent("x.wav"))
            XCTFail("expected an error for a file with no audio track")
        } catch { /* expected */ }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter AudioImporterTests`
Expected: FAIL — `cannot find 'AudioImporter' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/INMeetingsCore/Import/AudioImporter.swift`:

```swift
import AVFoundation
import Foundation

public enum AudioImportError: Error, LocalizedError {
    case noAudioTrack
    case conversionFailed(String)
    public var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "The file has no audio track."
        case .conversionFailed(let why): return "Couldn't read the audio: \(why)"
        }
    }
}

/// Decode the audio of any AVFoundation-readable container (m4a/mp3/aac/wav/caf/mp4/mov…) into a
/// 16 kHz mono 16-bit PCM WAV — the format the pipeline's ASR + senko diarizer expect (the live capture
/// already produces 16-bit WAVs). Video containers are handled by reading only their audio track.
public enum AudioImporter {
    public static func convertToWav16kMono(_ input: URL, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioImportError.noAudioTrack
        }

        let pcm: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: pcm)
        guard reader.canAdd(readerOutput) else { throw AudioImportError.conversionFailed("reader rejected output") }
        reader.add(readerOutput)

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: pcm)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw AudioImportError.conversionFailed("writer rejected input") }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw AudioImportError.conversionFailed(reader.error?.localizedDescription ?? "startReading failed")
        }
        guard writer.startWriting() else {
            throw AudioImportError.conversionFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "com.in-venture.audio-import")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let buffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(buffer)
                    } else {
                        writerInput.markAsFinished()
                        cont.resume()
                        return
                    }
                }
            }
        }
        await writer.finishWriting()

        if reader.status == .failed {
            throw AudioImportError.conversionFailed(reader.error?.localizedDescription ?? "reader failed")
        }
        guard writer.status == .completed else {
            throw AudioImportError.conversionFailed(writer.error?.localizedDescription ?? "writer failed")
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter AudioImporterTests`
Expected: PASS (2 tests). If `testThrowsWhenNoAudioTrack` is flaky because a 3-byte file is treated as readable, keep the assertion as "throws OR produces empty output" — but `loadTracks` returns empty for a non-media file, so `.noAudioTrack` should throw.

- [ ] **Step 5: Commit**

```bash
git add Sources/INMeetingsCore/Import/AudioImporter.swift Tests/INMeetingsCoreTests/AudioImporterTests.swift
git commit -m "feat(import): AVFoundation audio normalizer (→16 kHz mono WAV)"
```

---

## Task 5: JobBridge.enqueueImport

**Files:**
- Modify: `Sources/INMeetingsCore/JobBridge/JobBridge.swift`

No new unit test (it spawns the Python subprocess — covered by the Python contract test in Task 10 and the manual end-to-end test). Keep it thin: build job via `ImportJob.make`, write it, reuse the existing `spawn`. Crucially it does **not** run the live time-window calendar fetch — `context.input.json` is pre-written by the coordinator.

- [ ] **Step 1: Add `enqueueImport`**

In `JobBridge.swift`, after `enqueue(_:startedAt:endedAt:captureSourceApp:)`:

```swift
    /// Start the pipeline for an *imported* recording. The folder must already contain the normalized
    /// audio track (`audioFilename`) and — for the event-bound path — a pinned `context.input.json`
    /// (written by the import coordinator). Unlike `enqueue`, this does NOT fetch live calendar context.
    public func enqueueImport(directory: URL, audioFilename: String, startedAt: Date, endedAt: Date) {
        phase = nil
        lastError = nil
        let jobURL = directory.appendingPathComponent("job.json")
        let job = ImportJob.make(meetingId: directory.lastPathComponent, directory: directory,
                                 audioFilename: audioFilename, startedAt: startedAt, endedAt: endedAt)
        do {
            let data = try JSONSerialization.data(withJSONObject: job, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: jobURL, options: .atomic)
        } catch {
            lastError = "Failed to write job.json: \(error.localizedDescription)"
            phase = "failed"
            captureLog.error("jobbridge.import.writeJob failed: \(error.localizedDescription, privacy: .public)")
            recordFailure(folder: directory, error: lastError)
            return
        }
        let statusURL = directory.appendingPathComponent("status.json")
        phase = "queued"
        spawn(jobURL: jobURL, statusURL: statusURL)
    }
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/INMeetingsCore/JobBridge/JobBridge.swift
git commit -m "feat(jobbridge): enqueueImport — run the pipeline on a prepared import folder"
```

---

## Task 6: MeetingImporter — the import coordinator

**Files:**
- Create: `Sources/INMeetingsCore/Import/MeetingImporter.swift`
- Test: `Tests/INMeetingsCoreTests/MeetingImporterTests.swift` (create)

Coordinator with injected seams (so the test avoids AVFoundation + spawning Python): `convert`, `writePinnedContext`, `enqueue`. The app wires the real implementations (Task 9).

- [ ] **Step 1: Write the failing test**

Create `Tests/INMeetingsCoreTests/MeetingImporterTests.swift`:

```swift
import XCTest
import Foundation
@testable import INMeetingsCore

final class MeetingImporterTests: XCTestCase {
    private func event() -> CalendarEvent {
        CalendarEvent(id: "evt9", summary: "Sync",
                      start: .init(dateTime: "2026-06-22T09:00:00Z", date: nil),
                      end: .init(dateTime: "2026-06-22T09:30:00Z", date: nil),
                      hangoutLink: nil, attendees: nil)
    }

    func testEventImportCreatesFolderConvertsAndEnqueues() async throws {
        var enqueued: (URL, String, Date, Date)?
        var pinned: URL?
        let importer = MeetingImporter(
            convert: { _, out in try Data("wav".utf8).write(to: out) },
            writePinnedContext: { dir, _, _, _ in pinned = dir },
            enqueue: { dir, name, s, e in enqueued = (dir, name, s, e) })

        let src = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(UUID()).m4a")
        try Data("x".utf8).write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }

        let iso = ISO8601DateFormatter()
        let start = iso.date(from: "2026-06-22T09:00:00Z")!
        let end = iso.date(from: "2026-06-22T09:30:00Z")!
        let id = try await importer.importRecording(from: src, event: event(), start: start, end: end)

        let dir = RecordingsStore.root.appendingPathComponent(id)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("audio.wav").path))
        XCTAssertEqual(pinned, dir)                       // event path → pinned context written
        XCTAssertEqual(enqueued?.0, dir)
        XCTAssertEqual(enqueued?.1, "audio.wav")
        XCTAssertEqual(enqueued?.2, start)
    }

    func testNoEventImportSkipsPinnedContext() async throws {
        var pinnedCalled = false
        var enqueued = false
        let importer = MeetingImporter(
            convert: { _, out in try Data("wav".utf8).write(to: out) },
            writePinnedContext: { _, _, _, _ in pinnedCalled = true },
            enqueue: { _, _, _, _ in enqueued = true })

        let src = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(UUID()).m4a")
        try Data("x".utf8).write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }

        let id = try await importer.importRecording(from: src, event: nil, start: Date(), end: Date())
        defer { try? FileManager.default.removeItem(at: RecordingsStore.root.appendingPathComponent(id)) }
        XCTAssertFalse(pinnedCalled)
        XCTAssertTrue(enqueued)
    }

    func testConversionFailureCleansUpFolder() async throws {
        struct Boom: Error {}
        var enqueued = false
        let importer = MeetingImporter(
            convert: { _, _ in throw Boom() },
            writePinnedContext: { _, _, _, _ in },
            enqueue: { _, _, _, _ in enqueued = true })

        let src = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(UUID()).m4a")
        try Data("x".utf8).write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }

        do {
            _ = try await importer.importRecording(from: src, event: nil, start: Date(), end: Date())
            XCTFail("expected throw")
        } catch is Boom { /* expected */ }
        XCTAssertFalse(enqueued)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter MeetingImporterTests`
Expected: FAIL — `cannot find 'MeetingImporter' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/INMeetingsCore/Import/MeetingImporter.swift`:

```swift
import Foundation

/// Orchestrates importing an external recording into a new meeting folder, then handing it to the
/// pipeline. Seams are injected so it's unit-testable without AVFoundation or spawning Python; the app
/// wires the real `AudioImporter` / `CalendarContext.writePinnedInput` / `JobBridge.enqueueImport`.
public struct MeetingImporter {
    /// Decode + normalize `input` → 16 kHz mono WAV at `output`.
    public var convert: (_ input: URL, _ output: URL) async throws -> Void
    /// Write `context.input.json` pinned to the chosen event (event path only).
    public var writePinnedContext: (_ dir: URL, _ event: CalendarEvent, _ start: Date, _ end: Date) -> Void
    /// Kick the pipeline on the prepared folder.
    public var enqueue: (_ dir: URL, _ audioFilename: String, _ start: Date, _ end: Date) -> Void

    public init(
        convert: @escaping (URL, URL) async throws -> Void = AudioImporter.convertToWav16kMono,
        writePinnedContext: @escaping (URL, CalendarEvent, Date, Date) -> Void,
        enqueue: @escaping (URL, String, Date, Date) -> Void
    ) {
        self.convert = convert
        self.writePinnedContext = writePinnedContext
        self.enqueue = enqueue
    }

    /// Import `fileURL` as a new meeting. When `event` is non-nil the meeting is bound to it (context +
    /// attendees); `start`/`end` should be the event's window (or `Date()` for a no-event import). Returns
    /// the new meeting id (its folder name). Cleans up the folder if anything fails before enqueue.
    @discardableResult
    public func importRecording(from fileURL: URL, event: CalendarEvent?,
                                start: Date, end: Date) async throws -> String {
        let dir = uniqueMeetingDirectory(preferredStart: start)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let wav = dir.appendingPathComponent("audio.wav")
            try await convert(fileURL, wav)
            if let event { writePinnedContext(dir, event, start, end) }
            enqueue(dir, "audio.wav", start, end)
            return dir.lastPathComponent
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
    }

    /// A timestamped folder under the recordings root; bumps by a second if one already exists so two
    /// imports of the same event don't collide.
    private func uniqueMeetingDirectory(preferredStart: Date) -> URL {
        var when = preferredStart
        var dir = RecordingsStore.newMeetingDirectory(now: when)
        while FileManager.default.fileExists(atPath: dir.path) {
            when = when.addingTimeInterval(1)
            dir = RecordingsStore.newMeetingDirectory(now: when)
        }
        return dir
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter MeetingImporterTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/INMeetingsCore/Import/MeetingImporter.swift Tests/INMeetingsCoreTests/MeetingImporterTests.swift
git commit -m "feat(import): MeetingImporter coordinator (folder → normalize → pin context → enqueue)"
```

---

## Task 7: CalendarPanelModel — the day-agenda view model

**Files:**
- Create: `Sources/INMeetingsCore/Calendar/CalendarPanelModel.swift`
- Test: `Tests/INMeetingsCoreTests/CalendarPanelModelTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/INMeetingsCoreTests/CalendarPanelModelTests.swift`:

```swift
import XCTest
import Foundation
@testable import INMeetingsCore

private final class FakeCalendar: CalendarEventsProviding, @unchecked Sendable {
    var isConnected = true
    var callCount = 0
    var byDayKey: (Date) -> [CalendarEvent] = { _ in [] }
    func fetchEvents(timeMin: Date, timeMax: Date) async throws -> [CalendarEvent] {
        callCount += 1
        return byDayKey(timeMin)
    }
}

@MainActor
final class CalendarPanelModelTests: XCTestCase {
    private func event(_ id: String) -> CalendarEvent {
        CalendarEvent(id: id, summary: id, start: .init(dateTime: "2026-06-22T10:00:00Z", date: nil),
                      end: .init(dateTime: "2026-06-22T10:30:00Z", date: nil), hangoutLink: nil, attendees: nil)
    }

    func testLoadsSelectedDayThenCachesIt() async {
        let cal = FakeCalendar()
        cal.byDayKey = { _ in [self.event("a")] }
        let model = CalendarPanelModel(calendar: cal, recordedIds: { [] },
                                       today: ISO8601DateFormatter().date(from: "2026-06-22T08:00:00Z")!)
        await model.load()
        if case .loaded(let evs) = model.state { XCTAssertEqual(evs.map(\.id), ["a"]) }
        else { XCTFail("expected loaded") }
        await model.load()                       // second load → cache hit, no extra fetch
        XCTAssertEqual(cal.callCount, 1)
        await model.load(force: true)            // refresh → re-fetch
        XCTAssertEqual(cal.callCount, 2)
    }

    func testPagingChangesDayAndFetches() async {
        let cal = FakeCalendar()
        let model = CalendarPanelModel(calendar: cal, recordedIds: { [] },
                                       today: ISO8601DateFormatter().date(from: "2026-06-22T08:00:00Z")!)
        let day0 = model.selectedDay
        await model.load()
        await model.step(days: -1)               // go to older day
        XCTAssertEqual(model.selectedDay, Calendar.current.date(byAdding: .day, value: -1, to: day0))
        XCTAssertEqual(cal.callCount, 2)
    }

    func testErrorStateOnThrow() async {
        let cal = FakeCalendar()
        struct Boom: Error {}
        cal.byDayKey = { _ in [] }
        let throwing = FakeCalendar()
        throwing.byDayKey = { _ in [] }
        // Make fetch throw:
        final class Throwing: CalendarEventsProviding, @unchecked Sendable {
            var isConnected = true
            func fetchEvents(timeMin: Date, timeMax: Date) async throws -> [CalendarEvent] { throw Boom() }
        }
        let model = CalendarPanelModel(calendar: Throwing(), recordedIds: { [] }, today: Date())
        await model.load()
        if case .error = model.state {} else { XCTFail("expected error") }
    }

    func testIsRecordedReflectsRecordedIds() {
        let model = CalendarPanelModel(calendar: FakeCalendar(), recordedIds: { ["x"] }, today: Date())
        XCTAssertTrue(model.isRecorded(event("x")))
        XCTAssertFalse(model.isRecorded(event("y")))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter CalendarPanelModelTests`
Expected: FAIL — `cannot find 'CalendarPanelModel' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/INMeetingsCore/Calendar/CalendarPanelModel.swift`:

```swift
import Foundation
import Observation

/// Day-at-a-time agenda for the dashboard calendar panel. Holds the selected day, a per-day cache (paging
/// is instant; refresh forces a re-fetch), and which events already have a recording. Foundation-only +
/// `@Observable` so the SwiftUI panel observes it and it stays unit-testable in Core.
@MainActor
@Observable
public final class CalendarPanelModel {
    public enum DayState: Sendable {
        case loading
        case loaded([CalendarEvent])
        case error(String)
    }

    private let calendar: CalendarEventsProviding
    private let recordedIds: () -> Set<String>
    private var cache: [Date: [CalendarEvent]] = [:]

    public private(set) var selectedDay: Date
    public private(set) var state: DayState = .loading

    public init(calendar: CalendarEventsProviding, recordedIds: @escaping () -> Set<String>,
                today: Date = Date()) {
        self.calendar = calendar
        self.recordedIds = recordedIds
        self.selectedDay = Calendar.current.startOfDay(for: today)
    }

    public var isConnected: Bool { calendar.isConnected }

    /// Load the selected day. Cache hit returns instantly unless `force` (the ⟳ refresh).
    public func load(force: Bool = false) async {
        let day = selectedDay
        if !force, let cached = cache[day] { state = .loaded(cached); return }
        state = .loading
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        do {
            let events = try await calendar.fetchEvents(timeMin: start, timeMax: end)
            cache[day] = events
            if day == selectedDay { state = .loaded(events) }
        } catch {
            if day == selectedDay { state = .error(error.localizedDescription) }
        }
    }

    /// Move the agenda by `days` (−1 older, +1 newer) and load it.
    public func step(days: Int) async {
        selectedDay = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) ?? selectedDay
        await load()
    }

    /// Jump back to today and load it.
    public func goToToday(now: Date = Date()) async {
        selectedDay = Calendar.current.startOfDay(for: now)
        await load()
    }

    public func isRecorded(_ event: CalendarEvent) -> Bool { recordedIds().contains(event.id) }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter CalendarPanelModelTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the full core suite**

Run: `swift test`
Expected: PASS (all).

- [ ] **Step 6: Commit**

```bash
git add Sources/INMeetingsCore/Calendar/CalendarPanelModel.swift Tests/INMeetingsCoreTests/CalendarPanelModelTests.swift
git commit -m "feat(calendar): day-agenda panel view model (paging, cache, recorded markers)"
```

---

## Task 8: CalendarPanel — the SwiftUI inspector view

**Files:**
- Create: `Apps/INMeetings/INMeetings/Calendar/CalendarPanel.swift`

App-target view; verified by build + the manual checklist (no unit test). Provides: disconnected prompt, day header with ◀/Today/▶/⟳, event rows with time·title·attendee count + Upload action + "✓ recorded" (tappable), and the no-event footer.

- [ ] **Step 1: Implement the view**

Create `Apps/INMeetings/INMeetings/Calendar/CalendarPanel.swift`:

```swift
import SwiftUI
import INMeetingsCore

/// The dashboard's right-side day-agenda inspector. Pick an event → upload a recording bound to it, or
/// upload without an event from the footer. Gated on Google being connected.
struct CalendarPanel: View {
    let drive: DriveAuth
    @Bindable var model: CalendarPanelModel
    /// Called when the user chooses to upload for a specific event (nil = no-event footer).
    let onUpload: (CalendarEvent?) -> Void
    /// Called when the user taps an already-recorded event to open it.
    let onOpenRecorded: (CalendarEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if drive.isConnected {
                header
                Divider()
                content
                Divider()
                Button { onUpload(nil) } label: {
                    Label("Upload recording without an event…", systemImage: "waveform.badge.plus")
                }
                .buttonStyle(.borderless)
                .padding(12)
            } else {
                disconnected
            }
        }
        .frame(minWidth: 280)
        .task { await model.load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { Task { await model.step(days: -1) } } label: { Image(systemName: "chevron.left") }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.selectedDay, format: .dateTime.weekday(.wide))
                    .font(.headline)
                Text(model.selectedDay, format: .dateTime.month().day())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button { Task { await model.step(days: 1) } } label: { Image(systemName: "chevron.right") }
            Spacer()
            Button("Today") { Task { await model.goToToday() } }
                .buttonStyle(.borderless).font(.caption)
            Button { Task { await model.load(force: true) } } label: { Image(systemName: "arrow.clockwise") }
        }
        .buttonStyle(.borderless)
        .padding(12)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(24)
        case .error(let message):
            VStack(spacing: 8) {
                ContentUnavailableView("Couldn't load calendar", systemImage: "calendar.badge.exclamationmark",
                                       description: Text(message))
                Button("Retry") { Task { await model.load(force: true) } }
            }.padding(12)
        case .loaded(let events):
            if events.isEmpty {
                ContentUnavailableView("No events", systemImage: "calendar",
                                       description: Text("Nothing scheduled this day.")).padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(events, id: \.id) { event in row(event) }
                    }.padding(8)
                }
            }
        }
    }

    @ViewBuilder private func row(_ event: CalendarEvent) -> some View {
        let recorded = model.isRecorded(event)
        let timeLabel = Self.timeLabel(event)   // nil for all-day events → no upload action (spec)
        VStack(alignment: .leading, spacing: 2) {
            Text(event.summary ?? "(no title)").font(.subheadline).lineLimit(1)
            HStack(spacing: 6) {
                Text(timeLabel ?? "All day").font(.caption).foregroundStyle(.secondary)
                if let n = event.attendees?.count, n > 0 {
                    Text("· \(n) attendee\(n == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if recorded {
                    Label("recorded", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green).labelStyle(.titleAndIcon)
                } else if timeLabel != nil {
                    Button("Upload…") { onUpload(event) }.buttonStyle(.borderless).font(.caption)
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(recorded ? 0.4 : 0), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { if recorded { onOpenRecorded(event) } }
    }

    private var disconnected: some View {
        ContentUnavailableView {
            Label("Connect Google", systemImage: "calendar")
        } description: {
            Text("Connect your Google account to see your calendar and import recordings.")
        } actions: {
            Button("Connect Google…") { Task { await drive.connect() } }
        }
        .padding(12)
    }

    /// "10:00–10:30" for a timed event; nil for all-day (no time → not a recordable slot).
    static func timeLabel(_ event: CalendarEvent) -> String? {
        let iso = ISO8601DateFormatter()
        guard let s = event.start.dateTime.flatMap({ iso.date(from: $0) }),
              let e = event.end.dateTime.flatMap({ iso.date(from: $0) }) else { return nil }
        let f = Date.FormatStyle.dateTime.hour().minute()
        return "\(s.formatted(f))–\(e.formatted(f))"
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project (new app-target file) + build**

Run: `make gen && make build-mac`
Expected: Build succeeds. (If `CalendarPanel` references something missing, fix imports — it depends only on `DriveAuth`, `CalendarPanelModel`, `CalendarEvent`.)

- [ ] **Step 3: Commit**

```bash
git add -A Apps/INMeetings   # the new view + the regenerated .xcodeproj from `make gen`
git commit -m "feat(dashboard): calendar day-agenda inspector view"
```

---

## Task 9: Dashboard wiring — inspector toggle, file importer, store passthroughs

**Files:**
- Modify: `Apps/INMeetings/INMeetings/Dashboard/RecordingStore.swift`
- Modify: `Apps/INMeetings/INMeetings/Dashboard/DashboardWindow.swift`

- [ ] **Step 1: Add store passthroughs + the import entry point to RecordingStore**

Read `RecordingStore.swift` first (it wraps `MeetingStore` as `store` and exposes `meetings`, `selection`, `metadata(for:)`, `renameSpeaker`). Add:

```swift
    /// Calendar event ids that already have a recording (panel "✓ recorded" markers).
    func recordedCalendarEventIds() -> Set<String> {
        (try? store.calendarEventIdsWithRecording()) ?? []
    }

    /// Open the meeting bound to a calendar event (panel click-through).
    func openMeeting(forCalendarEventId eventId: String) {
        if let m = try? store.meeting(forCalendarEventId: eventId) { selection = .meeting(m.id) }
    }

    /// Import a recording (optionally bound to a calendar event) and select it once processing starts.
    /// Reloads the list when the pipeline finishes (the existing `.jobBridgeDidFinish` observer covers it).
    func importRecording(from fileURL: URL, event: CalendarEvent?, start: Date, end: Date) async {
        let importer = MeetingImporter(
            writePinnedContext: { dir, ev, s, e in CalendarContext().writePinnedInput(into: dir, event: ev, startedAt: s, endedAt: e) },
            enqueue: { dir, name, s, e in jobBridge.enqueueImport(directory: dir, audioFilename: name, startedAt: s, endedAt: e) })
        do {
            let id = try await importer.importRecording(from: fileURL, event: event, start: start, end: end)
            load()
            selection = .meeting(id)
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Surfaced as an alert by the dashboard when an import fails before processing.
    var importError: String?
```

(Confirm the property names `store`, `jobBridge`, `selection`, `load()` match `RecordingStore`'s actual members when you open the file; adjust if they differ.)

- [ ] **Step 2: Wire the inspector + file importer into DashboardWindow**

Replace the body of `DashboardWindow` to add the calendar panel model, the inspector toggle, and the file importer:

```swift
struct DashboardWindow: View {
    let drive: DriveAuth
    let jobBridge: JobBridge
    @State private var storeModel: RecordingStore
    @State private var calendarModel: CalendarPanelModel
    @AppStorage("showCalendarPanel") private var showCalendar = false
    @State private var importing = false
    @State private var pendingEvent: CalendarEvent?

    init(drive: DriveAuth, jobBridge: JobBridge) {
        self.drive = drive
        self.jobBridge = jobBridge
        let store = RecordingStore(drive: drive, jobBridge: jobBridge)
        _storeModel = State(initialValue: store)
        _calendarModel = State(initialValue: CalendarPanelModel(
            calendar: CalendarContext(),
            recordedIds: { [weak store] in store?.recordedCalendarEventIds() ?? [] }))
    }

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCalendar.toggle() } label: {
                    Label("Calendar", systemImage: "calendar")
                }
            }
        }
        .inspector(isPresented: $showCalendar) {
            CalendarPanel(drive: drive, model: calendarModel,
                          onUpload: { event in pendingEvent = event; importing = true },
                          onOpenRecorded: { event in storeModel.openMeeting(forCalendarEventId: event.id) })
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.audio, .movie, .mpeg4Movie, .quickTimeMovie],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .alert("Import failed", isPresented: Binding(
            get: { storeModel.importError != nil },
            set: { if !$0 { storeModel.importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(storeModel.importError ?? "") }
        .onAppear { storeModel.load() }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let event = pendingEvent
        let (start, end) = Self.window(for: event)
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            await storeModel.importRecording(from: url, event: event, start: start, end: end)
            pendingEvent = nil
        }
    }

    /// The meeting window: the event's start/end when bound, else "now" (no-event import).
    static func window(for event: CalendarEvent?) -> (Date, Date) {
        let iso = ISO8601DateFormatter()
        if let event,
           let s = event.start.dateTime.flatMap({ iso.date(from: $0) }),
           let e = event.end.dateTime.flatMap({ iso.date(from: $0) }) { return (s, e) }
        let now = Date()
        return (now, now)
    }

    @ViewBuilder private var content: some View { /* unchanged from current file */
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

Add `import UniformTypeIdentifiers` at the top of the file (for the `UTType` content types).

- [ ] **Step 3: Build**

Run: `make gen && make build-mac`
Expected: Build succeeds. Fix any member-name mismatches surfaced by the compiler (RecordingStore property names, `MeetingListView`/`needsLinking`/`processing` helpers are pre-existing).

- [ ] **Step 4: (optional) show the "Imported" badge in the list**

In `MeetingListView` (or the row view it uses), where the meeting row renders its subtitle/metadata, add a small badge when `meeting.source == "imported"`:

```swift
if meeting.source == "imported" {
    Text("Imported").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
        .background(.tint.opacity(0.15), in: Capsule()).foregroundStyle(.tint)
}
```

(Locate the row view by opening `MeetingListView.swift`; place the badge beside the existing company/title line.)

- [ ] **Step 5: Build again + commit**

Run: `make gen && make build-mac`
Expected: Build succeeds.

```bash
git add -A Apps/INMeetings
git commit -m "feat(dashboard): wire calendar inspector + file import + imported badge"
```

---

## Task 10: Python contract test — import-style job → metadata

**Files:**
- Create: `pipeline/tests/test_import.py`

Confirms the existing pipeline already serves the import contract. Both tests are **fully runnable offline** — no whisper/senko needed: `Job.load` tolerance is pure, and `run()` with **empty `tracks`** produces full metadata from context alone (this is exactly how `test_context.py::test_run_invokes_assembler_and_packages` works — `"tracks": {}` → no ASR). So the second test exercises the import-specific bits (source-key tolerance end-to-end, `profile: "inPerson"` → `type: "in_person"`, a pinned single candidate → `calendar_event_id` + attendees) without any audio. The single-track `tracks: ["mic"]` + Speaker-N behavior is already covered by `test_metadata.py::test_build_metadata_in_person_has_no_system_track` and `test_diarize.py`.

- [ ] **Step 1: Write the test**

Create `pipeline/tests/test_import.py`:

```python
"""The 'import an audio file assigned to a calendar event' contract: a single mixed track is processed as
profile 'inPerson', and a context.input.json pinned to exactly one event fills metadata with that event's
id + attendees. The extra job-level 'source' key must be ignored by Job.load."""
import json
from pathlib import Path

from in_meetings_pipeline.__main__ import run
from in_meetings_pipeline.job import Job


def test_import_job_tolerates_source_key(tmp_path: Path) -> None:
    job_json = {
        "meeting_id": "imp-1", "directory": str(tmp_path), "profile": "inPerson",
        "tracks": {"mic": "audio.wav"}, "started_at": "2026-06-22T10:00:00Z",
        "ended_at": "2026-06-22T10:30:00Z", "video": False, "source": "import",
    }
    p = tmp_path / "job.json"
    p.write_text(json.dumps(job_json), encoding="utf-8")
    job = Job.load(p)                      # must not raise on the unknown 'source' key
    assert job.profile == "inPerson"
    assert job.mic == tmp_path / "audio.wav"
    assert job.system is None


def test_pinned_single_candidate_fills_metadata(tmp_path: Path) -> None:
    # context.input.json pinned to ONE candidate whose window == the meeting window (100% overlap match).
    (tmp_path / "context.input.json").write_text(json.dumps({
        "status": "ok", "internal_domain": "in-venture.com",
        "hints": {"capture_source_app": "", "started_at": "2026-06-22T10:00:00Z",
                  "ended_at": "2026-06-22T10:30:00Z"},
        "candidates": [{
            "id": "evt123", "summary": "Acme intro",
            "start": "2026-06-22T10:00:00Z", "end": "2026-06-22T10:30:00Z", "has_link": True,
            "attendees": [{"email": "dana@acme.com", "displayName": "Dana Cohen", "organizer": False}],
        }],
    }), encoding="utf-8")
    # Empty tracks → run() assembles context + writes metadata with no audio (no whisper/senko), exactly
    # like test_context.py::test_run_invokes_assembler_and_packages. profile inPerson + the import source key.
    job = {"meeting_id": "imp-1", "directory": str(tmp_path), "profile": "inPerson",
           "tracks": {}, "started_at": "2026-06-22T10:00:00Z", "ended_at": "2026-06-22T10:30:00Z",
           "source": "import"}
    (tmp_path / "job.json").write_text(json.dumps(job), encoding="utf-8")

    assert run(tmp_path / "job.json") == 0
    md = json.loads((tmp_path / "metadata.json").read_text(encoding="utf-8"))
    assert md["meeting"]["calendar_event_id"] == "evt123"
    assert md["meeting"]["type"] == "in_person"
    assert any(a["email"] == "dana@acme.com" for a in md.get("attendees", []))
```

- [ ] **Step 2: Run the tests**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_import.py -v`
Expected: PASS (both).

- [ ] **Step 3: Lint + commit**

Run: `cd pipeline && uvx ruff check in_meetings_pipeline tests`
Expected: clean.

```bash
git add pipeline/tests/test_import.py
git commit -m "test(pipeline): import-style job (single track + pinned event) contract"
```

---

## Task 11: Full build, test, and manual verification

- [ ] **Step 1: Full Swift core suite**

Run: `swift test`
Expected: PASS (all, including the new import/calendar/store tests).

- [ ] **Step 2: Full app build**

Run: `make gen && make build-mac`
Expected: Build succeeds.

- [ ] **Step 3: Python suite**

Run: `cd pipeline && .venv/bin/python -m pytest tests/ && uvx ruff check in_meetings_pipeline tests`
Expected: PASS + clean.

- [ ] **Step 4: Manual test checklist (run the app — `make run-mac`)**

Build proves syntax, not behavior. Walk these with the app running (needs Google connected + `whisper-cli` on PATH):

1. **Panel opens:** toolbar Calendar button toggles the right inspector; it shows **today's** agenda.
2. **Paging + refresh:** ◀/▶ move days (instant after first load); **Today** returns; **⟳** re-syncs.
3. **Disconnected state:** with Google disconnected, the panel shows "Connect Google"; connecting reveals the agenda.
4. **Event import:** pick an event → **Upload…** → choose an `.m4a` → meeting appears in **All Meetings** with an **Imported** badge and "Processing", then resolves with the event's **company/title**; open it → **attendees appear as speaker-chip quick-picks** → assign two speakers → names persist (and re-upload to Drive if connected).
5. **"✓ recorded":** the just-imported event now shows **✓ recorded**; clicking the row opens that meeting.
6. **No-event import:** footer **Upload without an event…** → imports with no attendees/company; set company + speaker names by hand.
7. **Video container:** upload an `.mp4`/`.mov` → its audio is extracted and transcribed (no video player for imports).
8. **Failure path:** upload a non-media file → the "Import failed" alert appears; no orphan meeting is left in the list.

- [ ] **Step 5: Update HANDOFF.md + DECISIONS.md**

Record: the feature shipped; imports are processed `inPerson` (single-track) → `type: in_person` with provenance via the new `source` field; auto-summary stays call-only; `MeetingRecord` migration v4 added `source` + `calendarEventId`. Commit:

```bash
git add HANDOFF.md DECISIONS.md
git commit -m "docs: record calendar-upload-context implementation + decisions"
```

- [ ] **Step 6: Finish the branch**

Use the `superpowers:finishing-a-development-branch` skill to open the PR (or merge), per project convention. Run `/codex:adversarial-review` first if the diff exceeds 200 lines (it will).

---

## Notes for the implementer

- **New `INMeetingsCore` files are auto-built by SPM**; new **app-target** files (`CalendarPanel.swift`) need `make gen` before `make build-mac`.
- **Don't touch the frozen `metadata.json` schema** (ADR-005). Provenance (`source`) rides in `job.json` and is read at index time.
- The detail-view speaker chips already read `store.metadata(for:)?.attendees` — **do not** add a parallel attendee path; the pinned `context.input.json` is what makes them appear.
- If `RecordingStore`'s real member names differ from those used in Task 9, adjust the passthroughs to match — the file is the source of truth.
- Keep commits atomic per task (the plan is structured for one commit per task).
