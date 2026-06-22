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
