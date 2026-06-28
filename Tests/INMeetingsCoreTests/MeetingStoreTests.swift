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

    // MARK: - Delete + sort (PR 2)

    /// A lightweight "processing" row with a controllable id + start time, via `markProcessing`'s job.json read.
    private func makeJobFolder(id: String, startedAt: String) throws -> URL {
        let dir = URL(filePath: NSTemporaryDirectory())
            .appending(path: "sorttest-\(UUID().uuidString)").appending(path: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let job: [String: Any] = ["meeting_id": id, "profile": "call",
                                  "started_at": startedAt, "ended_at": startedAt]
        try JSONSerialization.data(withJSONObject: job).write(to: dir.appending(path: "job.json"))
        return dir
    }

    func testDeleteMeetingRemovesRowAndSummaries() throws {
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: fixture)
        try store.upsertSummary(meetingId: rec.id, recipeId: "saventa-summary", state: "done")
        XCTAssertEqual(try store.allMeetings().count, 1)
        XCTAssertEqual(try store.summaries(forMeeting: rec.id).count, 1)

        try store.deleteMeeting(id: rec.id)

        XCTAssertNil(try store.meeting(id: rec.id))
        XCTAssertEqual(try store.allMeetings().count, 0)
        XCTAssertEqual(try store.summaries(forMeeting: rec.id).count, 0)
    }

    func testDeleteMeetingIsIdempotent() throws {
        let store = try MeetingStore()
        try store.deleteMeeting(id: "never-existed")   // no throw, no-op
        XCTAssertEqual(try store.allMeetings().count, 0)
    }

    func testAllMeetingsSortByDateRespectsOrder() throws {
        let store = try MeetingStore()
        _ = try store.markProcessing(folder: makeJobFolder(id: "m-old", startedAt: "2026-01-01T10:00:00+00:00"))
        _ = try store.markProcessing(folder: makeJobFolder(id: "m-new", startedAt: "2026-06-01T10:00:00+00:00"))

        XCTAssertEqual(try store.allMeetings(sortBy: .dateNewest).map(\.id), ["m-new", "m-old"])
        XCTAssertEqual(try store.allMeetings(sortBy: .dateOldest).map(\.id), ["m-old", "m-new"])
    }

    // MARK: - Full-text transcript search (FTS5, PR 3)

    func testTranscriptSearchFindsMidTranscriptPhrase() throws {
        let store = try MeetingStore()
        _ = try store.indexPackage(at: fixture)
        // "ARR" appears only in the transcript body, never in the title/company.
        let hits = try store.searchTranscripts(query: "ARR")
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.allSatisfy { $0.meetingId == "golden-package" })
        XCTAssertTrue(hits.contains { $0.startTime > 0 })          // jump-to-moment time came back as a Double
    }

    func testTranscriptSearchMatchesHebrew() throws {
        let store = try MeetingStore()
        _ = try store.indexPackage(at: fixture)
        let hits = try store.searchTranscripts(query: "מיליון")    // "million" — appears in the body
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.meetingId, "golden-package")
    }

    func testTranscriptSearchSanitizesPunctuationAndNeverThrows() throws {
        let store = try MeetingStore()
        _ = try store.indexPackage(at: fixture)
        // Raw FTS5 would choke on stray quotes/parens/hyphens — our sanitizer must neutralize them.
        XCTAssertNoThrow(try store.searchTranscripts(query: "ARR\" ) (ה-"))
        // A punctuation-only query has no searchable terms → empty, not an error.
        XCTAssertEqual(try store.searchTranscripts(query: " -) (\" ").count, 0)
    }

    func testDeleteMeetingRemovesTranscriptSearchRows() throws {
        let store = try MeetingStore()
        _ = try store.indexPackage(at: fixture)
        XCTAssertFalse(try store.searchTranscripts(query: "ARR").isEmpty)
        try store.deleteMeeting(id: "golden-package")
        XCTAssertTrue(try store.searchTranscripts(query: "ARR").isEmpty)
    }

    func testBackfillPopulatesEmptyFtsFromExistingMeetings() throws {
        let store = try MeetingStore()
        // A meeting row created WITHOUT indexPackage (so FTS stays empty), pointing at a folder that has a
        // transcript.json — the exact shape of an old DB predating the FTS index.
        let dir = URL(filePath: NSTemporaryDirectory())
            .appending(path: "bf-\(UUID().uuidString)").appending(path: "meeting-x")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try FileManager.default.copyItem(at: fixture.appending(path: "transcript.json"),
                                         to: dir.appending(path: "transcript.json"))
        _ = try store.markProcessing(folder: dir)                  // row exists, FTS empty
        XCTAssertTrue(try store.searchTranscripts(query: "מיליון").isEmpty)

        store.backfillTranscriptSearchIfNeeded()

        let hits = try store.searchTranscripts(query: "מיליון")
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.meetingId, "meeting-x")
    }
}
