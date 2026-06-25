import XCTest
@testable import INMeetingsCore

/// Migration v5 + the per-(meeting, recipe) summary rows (multiple summaries per meeting, backend).
/// The existing `meeting.summaryState` rollup is covered by `MeetingStoreTests`; here we test the new
/// `meetingSummary` table and its upsert/fetch/delete accessors.
final class MeetingSummaryStoreTests: XCTestCase {
    private var fixture: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // INMeetingsCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appending(path: "schema/fixtures/golden-package")
    }

    func testMigrationV5CreatesEmptyTable() throws {
        let store = try MeetingStore()   // in-memory; migrator runs in init
        let rec = try store.indexPackage(at: fixture)
        XCTAssertEqual(try store.summaries(forMeeting: rec.id), [])   // no rows yet, table exists
    }

    func testUpsertInsertsAndFetches() throws {
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: fixture)

        try store.upsertSummary(meetingId: rec.id, recipeId: "saventa-summary",
                                state: "running", error: nil, sessionId: nil)
        let rows = try store.summaries(forMeeting: rec.id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.recipeId, "saventa-summary")
        XCTAssertEqual(rows.first?.state, "running")
        XCTAssertNil(rows.first?.error)
        XCTAssertNil(rows.first?.sessionId)
    }

    func testUpsertUpdatesInPlaceAndCoalescesSessionId() throws {
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: fixture)

        try store.upsertSummary(meetingId: rec.id, recipeId: "saventa-summary",
                                state: "running", error: nil, sessionId: nil)
        try store.upsertSummary(meetingId: rec.id, recipeId: "saventa-summary",
                                state: "done", error: nil, sessionId: "sess-1")
        // A later transition with nil sessionId must NOT clobber the captured one (COALESCE).
        try store.upsertSummary(meetingId: rec.id, recipeId: "saventa-summary",
                                state: "done", error: nil, sessionId: nil)

        let rows = try store.summaries(forMeeting: rec.id)
        XCTAssertEqual(rows.count, 1)                       // upsert, not duplicate
        XCTAssertEqual(rows.first?.state, "done")
        XCTAssertEqual(rows.first?.sessionId, "sess-1")     // preserved by COALESCE
    }

    func testUpsertCarriesErrorOnFailure() throws {
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: fixture)
        try store.upsertSummary(meetingId: rec.id, recipeId: "short-brief",
                                state: "failed", error: "claude not found", sessionId: nil)
        let row = try store.summaries(forMeeting: rec.id).first
        XCTAssertEqual(row?.state, "failed")
        XCTAssertEqual(row?.error, "claude not found")
    }

    func testTwoRecipesCoexistForOneMeeting() throws {
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: fixture)
        try store.upsertSummary(meetingId: rec.id, recipeId: "saventa-summary",
                                state: "done", error: nil, sessionId: "a")
        try store.upsertSummary(meetingId: rec.id, recipeId: "short-brief",
                                state: "done", error: nil, sessionId: "b")
        let rows = try store.summaries(forMeeting: rec.id)
        XCTAssertEqual(Set(rows.map(\.recipeId)), ["saventa-summary", "short-brief"])   // two distinct rows
    }

    func testDeleteSummaryRemovesOneRow() throws {
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: fixture)
        try store.upsertSummary(meetingId: rec.id, recipeId: "saventa-summary",
                                state: "done", error: nil, sessionId: nil)
        try store.upsertSummary(meetingId: rec.id, recipeId: "short-brief",
                                state: "done", error: nil, sessionId: nil)
        try store.deleteSummary(meetingId: rec.id, recipeId: "saventa-summary")
        let rows = try store.summaries(forMeeting: rec.id)
        XCTAssertEqual(rows.map(\.recipeId), ["short-brief"])   // only the other one remains
    }
}
