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
