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

    // MARK: - Recipe resolver + override seam (A2)

    func testMakeArgumentsPromptDoesNotContainSaventa() {
        // The prompt must be recipe-agnostic (decision 3 of A2).
        let args = SummaryRunner.makeArguments(folder: URL(fileURLWithPath: "/tmp/m"), systemPrompt: "SYS")
        let prompt = args[1]   // second element is the -p prompt text
        XCTAssertFalse(prompt.lowercased().contains("saventa"),
                       "makeArguments prompt should be recipe-agnostic, not mention Saventa")
    }

    func testAssembleSystemPromptUsesOverrideDir() throws {
        // Build a temp recipe dir with distinctive content.
        let tempRoot = URL(filePath: NSTemporaryDirectory()).appending(path: "sr-override-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try "# OVERRIDE RECIPE CONTENT".write(
            to: tempRoot.appendingPathComponent("recipe.md"), atomically: true, encoding: .utf8)

        let prompt = try SummaryRunner.assembleSystemPrompt(resourcesURL: tempRoot)
        XCTAssertTrue(prompt.contains("OVERRIDE RECIPE CONTENT"),
                      "assembleSystemPrompt should pick up content from the given URL")
        XCTAssertFalse(prompt.contains("Funding"),
                       "should NOT contain saventa-summary content when a different dir is used")
    }

    func testRunUsesRecipeOverrideDir() async throws {
        // Verify that when `recipeOverride` is supplied the runner uses its resourcesURL, not the
        // init-time `resourcesURL`. We stub the process so no real `claude` is spawned.
        let dir = try tempCopyOfGolden()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Build a distinctive temp recipe dir.
        let overrideRoot = URL(filePath: NSTemporaryDirectory())
            .appending(path: "sr-recipe-override-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: overrideRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: overrideRoot) }
        try "# DISTINCT OVERRIDE RECIPE".write(
            to: overrideRoot.appendingPathComponent("recipe.md"), atomically: true, encoding: .utf8)
        let overrideRecipe = SummaryRecipe(
            id: "override", displayName: "Override", resourcesURL: overrideRoot, isBuiltIn: false)

        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)

        let captured = Captured()
        let runner = SummaryRunner(
            store: store, resourcesURL: resourcesURL,   // init-time dir = saventa-summary
            claudeURL: URL(fileURLWithPath: "/usr/bin/true"),
            runProcessOverride: { args, folder, _ in
                // Pull the system prompt from --append-system-prompt arg
                if let idx = args.firstIndex(of: "--append-system-prompt"), idx + 1 < args.count {
                    await captured.set(args[idx + 1])
                }
                try? "# summary".write(to: folder.appendingPathComponent("summary.md"),
                                       atomically: true, encoding: .utf8)
                return .init(exitCode: 0, stdout: #"{"session_id":"s1"}"#)
            })

        await runner.run(meetingID: rec.id, folder: dir, recipeOverride: overrideRecipe)
        let capturedSystemPrompt = await captured.value

        XCTAssertTrue(capturedSystemPrompt.contains("DISTINCT OVERRIDE RECIPE"),
                      "runner should have assembled the prompt from the override recipe dir")
        XCTAssertFalse(capturedSystemPrompt.contains("Funding"),
                       "saventa-summary content must not leak into the override run")
    }

    func testRunUsesResolveResourcesURLClosure() async throws {
        // Verify that the `resolveResourcesURL` closure is used when no per-run override is given.
        let dir = try tempCopyOfGolden()
        defer { try? FileManager.default.removeItem(at: dir) }

        let resolveRoot = URL(filePath: NSTemporaryDirectory())
            .appending(path: "sr-resolve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: resolveRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: resolveRoot) }
        try "# RESOLVED RECIPE CONTENT".write(
            to: resolveRoot.appendingPathComponent("recipe.md"), atomically: true, encoding: .utf8)

        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)

        let captured = Captured()
        let resolveURL = resolveRoot
        let runner = SummaryRunner(
            store: store, resourcesURL: resourcesURL,   // init-time dir = saventa-summary (fallback)
            claudeURL: URL(fileURLWithPath: "/usr/bin/true"),
            resolveResourcesURL: { resolveURL },         // resolver returns the distinctive dir
            runProcessOverride: { args, folder, _ in
                if let idx = args.firstIndex(of: "--append-system-prompt"), idx + 1 < args.count {
                    await captured.set(args[idx + 1])
                }
                try? "# summary".write(to: folder.appendingPathComponent("summary.md"),
                                       atomically: true, encoding: .utf8)
                return .init(exitCode: 0, stdout: #"{"session_id":"s2"}"#)
            })

        await runner.run(meetingID: rec.id, folder: dir)
        let capturedSystemPrompt = await captured.value

        XCTAssertTrue(capturedSystemPrompt.contains("RESOLVED RECIPE CONTENT"),
                      "runner should have used the resolveResourcesURL closure")
    }
}

/// Sendable flag for asserting the Drive sync hook fired.
private actor Flag {
    var hit = false
    func set() { hit = true }
}

/// Sendable string box for capturing a value from a `@Sendable` closure.
private actor Captured {
    var value: String = ""
    func set(_ v: String) { value = v }
}
