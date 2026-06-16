import XCTest
@testable import INMeetingsCore

/// The saventa-summary auto-trigger (ADR-008, amended). The headless `claude -p` run itself is live-verify
/// only; here we test the pure seams + the orchestration (state transitions, Drive hand-off) via a stubbed
/// process so the success/failure paths don't depend on a real `claude`.
final class SummaryRunnerTests: XCTestCase {
    private var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // INMeetingsCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }
    private var resourcesURL: URL {
        repoRoot.appending(path: "Apps/INMeetings/INMeetings/Resources/skills/saventa-summary")
    }
    private var goldenFixture: URL { repoRoot.appending(path: "schema/fixtures/golden-package") }

    private func tempCopyOfGolden() throws -> URL {
        let dst = URL(filePath: NSTemporaryDirectory()).appending(path: "sr-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: goldenFixture, to: dst)
        return dst
    }

    // MARK: - Pure helpers

    func testAssembleSystemPromptIncludesRecipeAndAllHouseStyle() throws {
        let prompt = try SummaryRunner.assembleSystemPrompt(resourcesURL: resourcesURL)
        XCTAssertTrue(prompt.contains("**Funding **"))   // the recipe template, trailing space preserved
        for section in ["critical-analysis", "investment-thesis", "josh-preferences", "writing-style",
                        "anti-patterns", "example-summary", "style-analysis"] {
            XCTAssertTrue(prompt.contains("House style — \(section)"), "missing house-style: \(section)")
        }
        // The CRM files must never be vendored / inlined.
        XCTAssertFalse(prompt.contains("House style — crm-mappings"))
        XCTAssertFalse(prompt.contains("House style — sevanta-api-reference"))
    }

    func testMakeArgumentsHasHeadlessFlags() {
        let args = SummaryRunner.makeArguments(folder: URL(fileURLWithPath: "/tmp/m"), systemPrompt: "SYS-PROMPT")
        XCTAssertEqual(args.first, "-p")
        XCTAssertTrue(args.contains("--append-system-prompt"))
        XCTAssertTrue(args.contains("SYS-PROMPT"))
        XCTAssertTrue(args.contains("--permission-mode"))
        XCTAssertTrue(args.contains("acceptEdits"))
        XCTAssertEqual(args.last, "json")               // --output-format json
    }

    func testParseSessionID() {
        XCTAssertEqual(
            SummaryRunner.parseSessionID(fromJSON: #"{"type":"result","session_id":"abc-123","result":"ok"}"#),
            "abc-123")
        let jsonl = "{\"type\":\"system\"}\n{\"type\":\"result\",\"session_id\":\"xyz-9\"}"
        XCTAssertEqual(SummaryRunner.parseSessionID(fromJSON: jsonl), "xyz-9")
        XCTAssertNil(SummaryRunner.parseSessionID(fromJSON: "not json at all"))
    }

    func testResolveClaudeFindsExecutableOnPath() throws {
        let bin = URL(filePath: NSTemporaryDirectory()).appending(path: "bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bin) }
        let claude = bin.appendingPathComponent("claude")
        FileManager.default.createFile(atPath: claude.path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        let found = SummaryRunner.resolveClaudeURL(environment: ["PATH": bin.path])
        XCTAssertEqual(found?.lastPathComponent, "claude")
    }

    // MARK: - Orchestration (stubbed process)

    func testRunSuccessUpdatesStateAndSyncs() async throws {
        let dir = try tempCopyOfGolden()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)

        let flag = Flag()
        let runner = SummaryRunner(
            store: store, resourcesURL: resourcesURL,
            claudeURL: URL(fileURLWithPath: "/usr/bin/true"),   // bypass PATH resolution deterministically
            syncSummary: { _, _ in await flag.set() },
            runProcessOverride: { _, folder, _ in
                try? "**Team**\n>X".write(to: folder.appendingPathComponent("summary.md"),
                                          atomically: true, encoding: .utf8)
                return .init(exitCode: 0, stdout: #"{"type":"result","session_id":"sess-xyz"}"#)
            })

        await runner.run(meetingID: rec.id, folder: dir)

        let row = try store.meeting(id: rec.id)
        XCTAssertEqual(row?.summaryState, "done")
        XCTAssertEqual(row?.summarySessionId, "sess-xyz")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("summary.md").path))
        let synced = await flag.hit
        XCTAssertTrue(synced)
    }

    func testRunFailsWhenNoSummaryWritten() async throws {
        let dir = try tempCopyOfGolden()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)

        let runner = SummaryRunner(
            store: store, resourcesURL: resourcesURL,
            claudeURL: URL(fileURLWithPath: "/usr/bin/true"),
            runProcessOverride: { _, _, _ in .init(exitCode: 0, stdout: "{}") })   // exit 0 but no summary.md

        await runner.run(meetingID: rec.id, folder: dir)
        let row = try store.meeting(id: rec.id)
        XCTAssertEqual(row?.summaryState, "failed")
        XCTAssertNotNil(row?.summaryError)
    }

    func testRunFailsOnNonZeroExit() async throws {
        let dir = try tempCopyOfGolden()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)

        let runner = SummaryRunner(
            store: store, resourcesURL: resourcesURL,
            claudeURL: URL(fileURLWithPath: "/usr/bin/true"),
            runProcessOverride: { _, _, _ in .init(exitCode: 1, stdout: "boom") })

        await runner.run(meetingID: rec.id, folder: dir)
        XCTAssertEqual(try store.meeting(id: rec.id)?.summaryState, "failed")
    }
}

/// Sendable flag for asserting the Drive sync hook fired.
private actor Flag {
    var hit = false
    func set() { hit = true }
}
