import XCTest
@testable import INMeetingsCore

/// `reconcileAfterSummaryDelete` — the row-delete + file-removal + rollup-recompute + summary.md-mirror
/// orchestration behind `RecordingStore.deleteSummary` (T3 review fix). Exercised against an in-memory
/// `MeetingStore` + a temp package folder so the filesystem side (per-recipe files + the `summary.md`
/// mirror) is real.
final class SummaryReconcileTests: XCTestCase {

    // MARK: - Fixtures

    /// The golden context package (copied into a temp dir so its name becomes the meeting id and the
    /// `meeting` rollup row exists for `updateSummaryState` to update).
    private var goldenFixture: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // INMeetingsCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appending(path: "schema/fixtures/golden-package")
    }

    /// Copy the golden package into a unique temp folder and index it, returning (store, meetingId, folder).
    /// The meeting id == the temp folder name, so the helper's rollup updates hit a real row.
    private func makeIndexedMeeting() throws -> (store: MeetingStore, id: String, folder: URL) {
        let store = try MeetingStore()   // in-memory
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SummaryReconcileTests_\(UUID().uuidString)")
        try FileManager.default.copyItem(at: goldenFixture, to: folder)
        let rec = try store.indexPackage(at: folder)
        return (store, rec.id, folder)
    }

    /// Write a per-recipe summary file + the DB row, in the state given. Mirrors `summary.md` to the
    /// most-recent done file the way `SummaryRunner` does, so the starting on-disk state is realistic.
    private func addSummary(_ store: MeetingStore, meetingId: String, folder: URL,
                            recipeId: String, state: String, body: String, now: Date) throws {
        let summariesDir = folder.appendingPathComponent("summaries")
        try FileManager.default.createDirectory(at: summariesDir, withIntermediateDirectories: true)
        let perRecipe = summariesDir.appendingPathComponent("\(recipeId).md")
        try body.write(to: perRecipe, atomically: true, encoding: .utf8)
        try store.upsertSummary(meetingId: meetingId, recipeId: recipeId, state: state, now: now)
        try store.updateSummaryState(id: meetingId, state: state)
        if state == "done" {
            let mirror = folder.appendingPathComponent("summary.md")
            try? FileManager.default.removeItem(at: mirror)
            try FileManager.default.copyItem(at: perRecipe, to: mirror)
        }
    }

    private func fileExists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    override func tearDown() {
        // Temp dirs are unique per test; nothing global to clean. (Individual tests remove their folder.)
        super.tearDown()
    }

    // MARK: - Delete one of two

    func testDeleteOneOfTwoKeepsRemainingAndReMirrors() throws {
        let (store, id, folder) = try makeIndexedMeeting()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Two done summaries; saventa is the more recent, so summary.md currently mirrors it.
        try addSummary(store, meetingId: id, folder: folder, recipeId: "short-brief",
                       state: "done", body: "BRIEF", now: Date(timeIntervalSince1970: 1000))
        try addSummary(store, meetingId: id, folder: folder, recipeId: "saventa-summary",
                       state: "done", body: "SAVENTA", now: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(read(folder.appendingPathComponent("summary.md")), "SAVENTA")

        // Delete the most-recent one (saventa). short-brief remains and becomes the rollup + mirror.
        try reconcileAfterSummaryDelete(store: store, meetingId: id, recipeId: "saventa-summary", folder: folder)

        let rows = try store.summaries(forMeeting: id)
        XCTAssertEqual(rows.map(\.recipeId), ["short-brief"])           // only the other row remains
        XCTAssertFalse(fileExists(folder.appendingPathComponent("summaries/saventa-summary.md")))

        let rollup = try XCTUnwrap(store.meeting(id: id))
        XCTAssertEqual(rollup.summaryState, "done")                     // reflects the remaining row
        XCTAssertNil(rollup.summaryError)
        XCTAssertEqual(read(folder.appendingPathComponent("summary.md")), "BRIEF")  // re-mirrored
    }

    func testDeleteOneOfTwoRollupTakesRemainingFailedState() throws {
        let (store, id, folder) = try makeIndexedMeeting()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Older done, newer failed. Delete the (newer) failed → rollup must fall back to the done row,
        // not stay "failed".
        try addSummary(store, meetingId: id, folder: folder, recipeId: "short-brief",
                       state: "done", body: "BRIEF", now: Date(timeIntervalSince1970: 1000))
        // A failed summary: row says failed, no done mirror update.
        try store.upsertSummary(meetingId: id, recipeId: "saventa-summary", state: "failed",
                                error: "boom", now: Date(timeIntervalSince1970: 2000))
        try store.updateSummaryState(id: id, state: "failed", error: "boom")

        try reconcileAfterSummaryDelete(store: store, meetingId: id, recipeId: "saventa-summary", folder: folder)

        let rollup = try XCTUnwrap(store.meeting(id: id))
        XCTAssertEqual(rollup.summaryState, "done")     // the remaining (done) row, not the deleted failed one
        XCTAssertNil(rollup.summaryError)
        XCTAssertEqual(read(folder.appendingPathComponent("summary.md")), "BRIEF")
    }

    func testDeleteDoneLeavingOnlyFailedDropsMirror() throws {
        let (store, id, folder) = try makeIndexedMeeting()
        defer { try? FileManager.default.removeItem(at: folder) }

        // A done (older) and a failed (newer). Delete the done → only a failed remains: no done row, so
        // summary.md must be removed (nothing valid to mirror).
        try addSummary(store, meetingId: id, folder: folder, recipeId: "short-brief",
                       state: "done", body: "BRIEF", now: Date(timeIntervalSince1970: 1000))
        try store.upsertSummary(meetingId: id, recipeId: "saventa-summary", state: "failed",
                                error: "boom", now: Date(timeIntervalSince1970: 2000))
        try store.updateSummaryState(id: id, state: "failed", error: "boom")
        XCTAssertTrue(fileExists(folder.appendingPathComponent("summary.md")))   // mirrors the done one

        try reconcileAfterSummaryDelete(store: store, meetingId: id, recipeId: "short-brief", folder: folder)

        let rows = try store.summaries(forMeeting: id)
        XCTAssertEqual(rows.map(\.recipeId), ["saventa-summary"])
        let rollup = try XCTUnwrap(store.meeting(id: id))
        XCTAssertEqual(rollup.summaryState, "failed")        // the remaining failed row
        XCTAssertEqual(rollup.summaryError, "boom")
        XCTAssertFalse(fileExists(folder.appendingPathComponent("summary.md")))  // no done row → mirror gone
    }

    // MARK: - Delete the last summary (the phantom / stuck-Queue regression)

    func testDeleteLastClearsMirrorAndRollupAndNoPhantom() throws {
        let (store, id, folder) = try makeIndexedMeeting()
        defer { try? FileManager.default.removeItem(at: folder) }

        try addSummary(store, meetingId: id, folder: folder, recipeId: "saventa-summary",
                       state: "done", body: "SAVENTA", now: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(fileExists(folder.appendingPathComponent("summary.md")))

        try reconcileAfterSummaryDelete(store: store, meetingId: id, recipeId: "saventa-summary", folder: folder)

        // Rows empty, mirror gone, rollup cleared.
        XCTAssertTrue(try store.summaries(forMeeting: id).isEmpty)
        XCTAssertFalse(fileExists(folder.appendingPathComponent("summary.md")))
        let rollup = try XCTUnwrap(store.meeting(id: id))
        XCTAssertNil(rollup.summaryState)
        XCTAssertNil(rollup.summaryError)

        // The crux: makeSummaryEntries over the now-empty rows + gone summary.md yields NO entries —
        // i.e. the legacy fallback can't resurrect a phantom "saventa-summary done" entry.
        let entries = makeSummaryEntries(rows: try store.summaries(forMeeting: id),
                                         folderURL: folder, displayName: { $0 })
        XCTAssertTrue(entries.isEmpty)
    }

    func testDeleteLastFailedClearsStuckQueueRollup() throws {
        // A meeting whose only summary failed (or was running) must not stay pinned in the Queue/Processing
        // view, which keys off summaryState — deleting it clears the rollup.
        let (store, id, folder) = try makeIndexedMeeting()
        defer { try? FileManager.default.removeItem(at: folder) }

        try store.upsertSummary(meetingId: id, recipeId: "saventa-summary", state: "failed",
                                error: "boom", now: Date(timeIntervalSince1970: 1000))
        try store.updateSummaryState(id: id, state: "failed", error: "boom")

        try reconcileAfterSummaryDelete(store: store, meetingId: id, recipeId: "saventa-summary", folder: folder)

        XCTAssertTrue(try store.summaries(forMeeting: id).isEmpty)
        let rollup = try XCTUnwrap(store.meeting(id: id))
        XCTAssertNil(rollup.summaryState)   // Queue no longer pins this meeting
        XCTAssertNil(rollup.summaryError)
    }

    // MARK: - Idempotence / missing-file safety

    func testDeleteIsBestEffortWhenFilesAbsent() throws {
        // Row present but the per-recipe file never existed and there is no summary.md — must not throw.
        let (store, id, folder) = try makeIndexedMeeting()
        defer { try? FileManager.default.removeItem(at: folder) }
        try store.upsertSummary(meetingId: id, recipeId: "saventa-summary", state: "done",
                                now: Date(timeIntervalSince1970: 1000))
        try store.updateSummaryState(id: id, state: "done")

        XCTAssertNoThrow(try reconcileAfterSummaryDelete(
            store: store, meetingId: id, recipeId: "saventa-summary", folder: folder))
        XCTAssertTrue(try store.summaries(forMeeting: id).isEmpty)
        XCTAssertNil(try XCTUnwrap(store.meeting(id: id)).summaryState)
    }
}
