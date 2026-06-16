import XCTest
@testable import INMeetingsCore

/// The SQLite index (ADR-006): indexing a finished package folder yields a queryable row.
final class MeetingStoreTests: XCTestCase {
    private var fixture: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // INMeetingsCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appending(path: "schema/fixtures/golden-package")
    }

    func testIndexGoldenPackageInsertsRow() throws {
        let store = try MeetingStore()  // in-memory
        let rec = try store.indexPackage(at: fixture)

        XCTAssertEqual(rec.id, "golden-package")  // folder name is the local meeting id
        XCTAssertEqual(rec.company, "Prelligence")
        XCTAssertEqual(rec.title, "Prelligence — Series A intro")
        XCTAssertEqual(rec.type, "call")
        XCTAssertEqual(rec.speakerCount, 2)
        XCTAssertTrue(rec.diarized)
        XCTAssertTrue(rec.biased)
        XCTAssertEqual(rec.consentStatus, "verbal")
        XCTAssertEqual(rec.syncState, "local")
        XCTAssertNil(rec.driveFolderId)
    }

    func testIndexIsIdempotent() throws {
        let store = try MeetingStore()
        _ = try store.indexPackage(at: fixture)
        _ = try store.indexPackage(at: fixture)
        XCTAssertEqual(try store.allMeetings().count, 1)
    }

    func testFetchByIdRoundTrips() throws {
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: fixture)

        let fetched = try store.meeting(id: rec.id)
        XCTAssertEqual(fetched?.company, "Prelligence")
        XCTAssertEqual(fetched?.startedAt, "2026-05-12T14:30:00+03:00")
        XCTAssertEqual(fetched?.modelRevision, "ivrit-large-v3-turbo")
    }

    func testUpdateCompanyChangesAndClearsTheRow() throws {
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: fixture)
        try store.updateCompany(id: rec.id, name: "Acme AI")
        XCTAssertEqual(try store.meeting(id: rec.id)?.company, "Acme AI")
        try store.updateCompany(id: rec.id, name: nil)
        XCTAssertNil(try store.meeting(id: rec.id)?.company)
    }

    // MARK: - Reliability pass: pipeline-failure surfacing

    func testMarkFailedWritesAFailedRowFromJob() throws {
        let store = try MeetingStore()
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "mf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let job: [String: Any] = ["meeting_id": dir.lastPathComponent, "profile": "inPerson",
                                  "started_at": "2026-06-15T09:00:00Z", "ended_at": "2026-06-15T09:10:00Z",
                                  "capture_source_app": "Zoom"]
        try JSONSerialization.data(withJSONObject: job).write(to: dir.appendingPathComponent("job.json"))

        let rec = try store.markFailed(folder: dir, error: "whisper-cli failed: boom")
        XCTAssertEqual(rec.status, "failed")
        XCTAssertEqual(rec.type, "in_person")                       // profile → type
        XCTAssertEqual(rec.startedAt, "2026-06-15T09:00:00Z")       // read back from job.json
        XCTAssertEqual(rec.captureSourceApp, "Zoom")
        XCTAssertEqual(rec.pipelineError, "whisper-cli failed: boom")
        XCTAssertEqual(try store.meeting(id: rec.id)?.status, "failed")
    }

    func testMarkFailedFallsBackWithoutJob() throws {
        let store = try MeetingStore()
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "mf2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let rec = try store.markFailed(folder: dir, error: nil)
        XCTAssertEqual(rec.status, "failed")
        XCTAssertEqual(rec.type, "call")        // default when there's no job.json to read
        XCTAssertNotNil(rec.pipelineError)      // a default message is filled in for the UI
    }

    func testSuccessfulIndexClearsAPriorFailure() throws {
        let store = try MeetingStore()
        _ = try store.markFailed(folder: fixture, error: "boom")   // the golden meeting "failed" first…
        XCTAssertEqual(try store.meeting(id: "golden-package")?.status, "failed")
        let rec = try store.indexPackage(at: fixture)              // …then a later run succeeds + clears it
        XCTAssertEqual(rec.status, "transcribed")
        XCTAssertNil(try store.meeting(id: "golden-package")?.pipelineError)
        XCTAssertEqual(try store.allMeetings().count, 1)           // same id, upserted (not duplicated)
    }

    // MARK: - Saventa-summary auto-trigger state (migration v3)

    func testSummaryStateDefaultsNilThenUpdates() throws {
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: fixture)
        XCTAssertNil(rec.summaryState)              // a freshly-indexed meeting has no summary yet
        XCTAssertNil(try store.meeting(id: rec.id)?.summarySessionId)

        try store.updateSummaryState(id: rec.id, state: "running")
        XCTAssertEqual(try store.meeting(id: rec.id)?.summaryState, "running")

        try store.updateSummaryState(id: rec.id, state: "done", sessionId: "sess-123")
        let done = try store.meeting(id: rec.id)
        XCTAssertEqual(done?.summaryState, "done")
        XCTAssertNil(done?.summaryError)
        XCTAssertEqual(done?.summarySessionId, "sess-123")
    }

    func testSummaryFailedCarriesErrorAndKeepsSessionId() throws {
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: fixture)
        try store.updateSummaryState(id: rec.id, state: "done", sessionId: "sess-abc")
        try store.updateSummaryState(id: rec.id, state: "failed", error: "claude not found")
        let row = try store.meeting(id: rec.id)
        XCTAssertEqual(row?.summaryState, "failed")
        XCTAssertEqual(row?.summaryError, "claude not found")
        XCTAssertEqual(row?.summarySessionId, "sess-abc")   // COALESCE preserves the prior session id
    }
}
