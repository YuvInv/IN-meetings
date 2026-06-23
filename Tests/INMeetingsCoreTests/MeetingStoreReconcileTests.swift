import XCTest
import Foundation
@testable import INMeetingsCore

/// Reconcile + processing-row behaviour: a meeting whose completion the live watcher missed (app relaunched
/// mid-transcription) must still appear after a launch, and a just-started job must show as "processing".
final class MeetingStoreReconcileTests: XCTestCase {
    private func tempRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("reconcile-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeFolder(in root: URL, id: String, metadata: Bool, job: Bool) -> URL {
        let dir = root.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if metadata {
            let md = """
            {"schema_version":"1.0",
             "meeting":{"start":"2026-06-22T10:00:00Z","end":"2026-06-22T10:30:00Z","type":"in_person"},
             "recording":{"tracks":["mic"],"video":false},
             "transcription":{"engine":"whisper.cpp","model_revision":"rev","language":"he","biased":false}}
            """
            try? md.write(to: dir.appendingPathComponent("metadata.json"), atomically: true, encoding: .utf8)
        }
        if job {
            try? "{\"profile\":\"inPerson\",\"source\":\"imported\",\"started_at\":\"2026-06-22T10:00:00Z\",\"ended_at\":\"2026-06-22T10:30:00Z\"}"
                .write(to: dir.appendingPathComponent("job.json"), atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testReconcileIndexesOrphanedCompletedMeeting() throws {
        let store = try MeetingStore()
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = makeFolder(in: root, id: "imp-done", metadata: true, job: true)

        XCTAssertNil(try store.meeting(id: "imp-done"))   // watcher missed it → not indexed
        store.reconcile(recordingsRoot: root)
        XCTAssertEqual(try store.meeting(id: "imp-done")?.status, "transcribed")  // self-healed
    }

    func testReconcileSurfacesInFlightJobAsProcessing() throws {
        let store = try MeetingStore()
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = makeFolder(in: root, id: "imp-running", metadata: false, job: true)

        store.reconcile(recordingsRoot: root)
        XCTAssertEqual(try store.meeting(id: "imp-running")?.status, "processing")
    }

    func testMarkProcessingDoesNotClobberFinishedMeeting() throws {
        let store = try MeetingStore()
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = makeFolder(in: root, id: "imp-x", metadata: true, job: true)

        _ = try store.markProcessing(folder: folder)
        XCTAssertEqual(try store.meeting(id: "imp-x")?.status, "processing")
        _ = try store.indexPackage(at: folder)
        XCTAssertEqual(try store.meeting(id: "imp-x")?.status, "transcribed")
        _ = try store.markProcessing(folder: folder)                       // must not revert to processing
        XCTAssertEqual(try store.meeting(id: "imp-x")?.status, "transcribed")
    }
}
