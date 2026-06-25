import XCTest
@testable import INMeetingsCore

final class SummaryEntriesTests: XCTestCase {

    // MARK: - Helpers

    private func row(_ recipeId: String, state: String, updatedAt: String,
                     error: String? = nil) -> MeetingSummary {
        MeetingSummary(meetingId: "m1", recipeId: recipeId, state: state,
                       error: error, sessionId: nil, updatedAt: updatedAt)
    }

    /// A temp dir with a `summary.md` file inside (legacy-fallback scenario).
    private func tempDirWithLegacySummary() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SummaryEntriesTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "summary text".write(to: dir.appendingPathComponent("summary.md"),
                                 atomically: true, encoding: .utf8)
        return dir
    }

    private func emptyTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SummaryEntriesTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - makeSummaryEntries

    func testMapsRowsToEntriesMostRecentFirst() {
        let rows = [
            row("short-brief", state: "done", updatedAt: "2026-06-25T10:00:00Z"),
            row("saventa-summary", state: "done", updatedAt: "2026-06-25T11:00:00Z"),
        ]
        let entries = makeSummaryEntries(rows: rows, folderURL: URL(fileURLWithPath: "/tmp"),
                                        displayName: { $0.uppercased() })
        // Most-recent first: saventa (11:00) before short-brief (10:00).
        XCTAssertEqual(entries.map(\.id), ["saventa-summary", "short-brief"])
        XCTAssertEqual(entries.first?.displayName, "SAVENTA-SUMMARY")
    }

    func testMapsStateAndError() {
        let rows = [row("r1", state: "failed", updatedAt: "2026-06-25T12:00:00Z", error: "boom")]
        let entries = makeSummaryEntries(rows: rows, folderURL: URL(fileURLWithPath: "/tmp"),
                                        displayName: { $0 })
        XCTAssertEqual(entries.first?.state, "failed")
        XCTAssertEqual(entries.first?.error, "boom")
    }

    func testLegacyFallbackWhenNoRowsButSummaryMdExists() throws {
        let dir = try tempDirWithLegacySummary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entries = makeSummaryEntries(rows: [], folderURL: dir,
                                        displayName: { _ in "Saventa Summary" })
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, "saventa-summary")
        XCTAssertEqual(entries.first?.state, "done")
        XCTAssertEqual(entries.first?.displayName, "Saventa Summary")
        XCTAssertNil(entries.first?.error)
    }

    func testLegacyFallbackReturnsEmptyWhenNoRowsAndNoFile() throws {
        let dir = try emptyTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entries = makeSummaryEntries(rows: [], folderURL: dir,
                                        displayName: { $0 })
        XCTAssertTrue(entries.isEmpty)
    }

    func testRealRowsTakePriorityOverLegacyFile() throws {
        // When rows are present the fallback should not fire, even if summary.md exists.
        let dir = try tempDirWithLegacySummary()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rows = [row("short-brief", state: "done", updatedAt: "2026-06-25T10:00:00Z")]
        let entries = makeSummaryEntries(rows: rows, folderURL: dir, displayName: { $0 })
        XCTAssertEqual(entries.map(\.id), ["short-brief"])
    }

    // MARK: - defaultSelectedEntry

    func testDefaultSelectsCurrentIfPresent() {
        let entries = [
            SummaryEntry(id: "a", displayName: "A", state: "done"),
            SummaryEntry(id: "b", displayName: "B", state: "done"),
        ]
        let chosen = defaultSelectedEntry(current: "b", entries: entries)
        XCTAssertEqual(chosen?.id, "b")
    }

    func testDefaultFallsToFirstDoneWhenCurrentGone() {
        let entries = [
            SummaryEntry(id: "a", displayName: "A", state: "running"),
            SummaryEntry(id: "b", displayName: "B", state: "done"),
        ]
        let chosen = defaultSelectedEntry(current: "missing", entries: entries)
        XCTAssertEqual(chosen?.id, "b")   // first "done"
    }

    func testDefaultFallsToFirstEntryWhenNoDone() {
        let entries = [
            SummaryEntry(id: "a", displayName: "A", state: "running"),
            SummaryEntry(id: "b", displayName: "B", state: "failed"),
        ]
        let chosen = defaultSelectedEntry(current: nil, entries: entries)
        XCTAssertEqual(chosen?.id, "a")   // first entry, no "done" present
    }

    func testDefaultReturnsNilWhenEmpty() {
        XCTAssertNil(defaultSelectedEntry(current: nil, entries: []))
    }

    func testDefaultKeepsNilCurrentAndPicksDone() {
        let entries = [
            SummaryEntry(id: "a", displayName: "A", state: "running"),
            SummaryEntry(id: "b", displayName: "B", state: "done"),
        ]
        let chosen = defaultSelectedEntry(current: nil, entries: entries)
        XCTAssertEqual(chosen?.id, "b")
    }
}
