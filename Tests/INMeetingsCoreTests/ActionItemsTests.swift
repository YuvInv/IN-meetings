import XCTest
@testable import INMeetingsCore

final class ActionItemsTests: XCTestCase {
    func testDecodesItemsIncludingNilOwnerAndDue() throws {
        let json = """
        {"recipeId":"saventa-summary","generatedAt":"2026-06-25T10:00:00Z","items":[
          {"task":"Send the data room","owner":"Yuval","status":"open","dueDate":"2026-07-01"},
          {"task":"Review the cap table","status":"in-progress"}
        ]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ActionItems.self, from: json)
        XCTAssertEqual(decoded.recipeId, "saventa-summary")
        XCTAssertEqual(decoded.items.count, 2)
        XCTAssertEqual(decoded.items[0].owner, "Yuval")
        XCTAssertEqual(decoded.items[0].dueDate, "2026-07-01")
        XCTAssertNil(decoded.items[1].owner)        // omitted owner → nil
        XCTAssertNil(decoded.items[1].dueDate)
        XCTAssertEqual(decoded.items[1].status, "in-progress")
    }

    func testDecodesMinimalItemsOnlyPayload() throws {
        let json = #"{"items":[{"task":"Follow up","status":"open"}]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ActionItems.self, from: json)
        XCTAssertNil(decoded.recipeId)
        XCTAssertNil(decoded.generatedAt)
        XCTAssertEqual(decoded.items.count, 1)
    }

    func testDeterministicIDStableForSameTaskAndOwnerDiffersOtherwise() {
        let a = ActionItem(task: "Send deck", owner: "Yuval")
        let b = ActionItem(task: "Send deck", owner: "Yuval", status: "done", dueDate: "2026-07-01")
        let c = ActionItem(task: "Send deck", owner: "Dana")
        XCTAssertEqual(a.id, b.id)   // id ignores status/dueDate — same task+owner → same id across re-runs
        XCTAssertNotEqual(a.id, c.id)
    }

    func testLoaderReturnsNilWhenAbsent() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(ActionItemsLoader.load(forMeetingFolder: dir, recipeId: "saventa-summary"))
    }

    func testLoaderReturnsNilWhenMalformed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let summaries = dir.appendingPathComponent("summaries")
        try FileManager.default.createDirectory(at: summaries, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "not json".data(using: .utf8)!.write(to: summaries.appendingPathComponent("r-actions.json"))
        XCTAssertNil(ActionItemsLoader.load(forMeetingFolder: dir, recipeId: "r"))
    }

    func testLoaderParsesValidFixture() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let summaries = dir.appendingPathComponent("summaries")
        try FileManager.default.createDirectory(at: summaries, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = #"{"items":[{"task":"Intro to a design partner","owner":"Dana","status":"blocked"}]}"#
        try payload.data(using: .utf8)!.write(to: summaries.appendingPathComponent("saventa-summary-actions.json"))
        let loaded = ActionItemsLoader.load(forMeetingFolder: dir, recipeId: "saventa-summary")
        XCTAssertEqual(loaded?.items.first?.task, "Intro to a design partner")
        XCTAssertEqual(loaded?.items.first?.status, "blocked")
    }
}
