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
        let args = SummaryRunner.makeArguments(folder: URL(fileURLWithPath: "/tmp/m"),
                                               relativeOutputPath: "summaries/saventa-summary.md",
                                               systemPrompt: "SYS-PROMPT")
        XCTAssertEqual(args.first, "-p")
        XCTAssertTrue(args.contains("--append-system-prompt"))
        XCTAssertTrue(args.contains("SYS-PROMPT"))
        XCTAssertTrue(args.contains("--permission-mode"))
        XCTAssertTrue(args.contains("acceptEdits"))
        XCTAssertEqual(args.last, "json")               // --output-format json
        XCTAssertTrue(args[1].contains("summaries/saventa-summary.md"))   // prompt names the per-recipe path
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
            store: store, resourcesURL: resourcesURL,   // fallback id = "saventa-summary"
            claudeURL: URL(fileURLWithPath: "/usr/bin/true"),   // bypass PATH resolution deterministically
            syncSummary: { _, _, _ in await flag.set() },
            runProcessOverride: { _, folder, _ in
                // The runner creates `summaries/` and tells claude to write there; emulate that here.
                try? "**Team**\n>X".write(to: folder.appendingPathComponent("summaries/saventa-summary.md"),
                                          atomically: true, encoding: .utf8)
                return .init(exitCode: 0, stdout: #"{"type":"result","session_id":"sess-xyz"}"#)
            })

        await runner.run(meetingID: rec.id, folder: dir)

        // Rollup (back-compat for the list + pre-T3 detail view).
        let row = try store.meeting(id: rec.id)
        XCTAssertEqual(row?.summaryState, "done")
        XCTAssertEqual(row?.summarySessionId, "sess-xyz")
        // Per-recipe row.
        let perRecipe = try store.summaries(forMeeting: rec.id)
        XCTAssertEqual(perRecipe.count, 1)
        XCTAssertEqual(perRecipe.first?.recipeId, "saventa-summary")
        XCTAssertEqual(perRecipe.first?.state, "done")
        XCTAssertEqual(perRecipe.first?.sessionId, "sess-xyz")
        // Per-recipe file written + mirrored to summary.md (downstream skills + current UI).
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("summaries/saventa-summary.md").path))
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
        // The per-recipe row is also "failed", and no summary.md mirror was written on failure.
        let perRecipe = try store.summaries(forMeeting: rec.id)
        XCTAssertEqual(perRecipe.first?.state, "failed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("summary.md").path))
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
        // The prompt must be recipe-agnostic (decision 3 of A2). The output path is the recipe id, but the
        // bundled default ("saventa-summary") is replaced here with a neutral one to keep the assertion sharp.
        let args = SummaryRunner.makeArguments(folder: URL(fileURLWithPath: "/tmp/m"),
                                               relativeOutputPath: "summaries/short-brief.md", systemPrompt: "SYS")
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
                try? "# summary".write(to: folder.appendingPathComponent("summaries/override.md"),
                                       atomically: true, encoding: .utf8)
                return .init(exitCode: 0, stdout: #"{"session_id":"s1"}"#)
            })

        await runner.run(meetingID: rec.id, folder: dir, recipeOverride: overrideRecipe)
        let capturedSystemPrompt = await captured.value

        XCTAssertTrue(capturedSystemPrompt.contains("DISTINCT OVERRIDE RECIPE"),
                      "runner should have assembled the prompt from the override recipe dir")
        XCTAssertFalse(capturedSystemPrompt.contains("Funding"),
                       "saventa-summary content must not leak into the override run")
        // The override recipe's file is written under its own id.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("summaries/override.md").path))
        XCTAssertEqual(try store.summaries(forMeeting: rec.id).first?.recipeId, "override")
    }

    func testRunUsesResolveActiveRecipeClosure() async throws {
        // Verify the `resolveActiveRecipe` closure is used when no per-run override is given.
        let dir = try tempCopyOfGolden()
        defer { try? FileManager.default.removeItem(at: dir) }

        let resolveRoot = URL(filePath: NSTemporaryDirectory())
            .appending(path: "sr-resolve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: resolveRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: resolveRoot) }
        try "# RESOLVED RECIPE CONTENT".write(
            to: resolveRoot.appendingPathComponent("recipe.md"), atomically: true, encoding: .utf8)
        let resolved = SummaryRecipe(id: "resolved", displayName: "Resolved",
                                     resourcesURL: resolveRoot, isBuiltIn: false)

        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)

        let captured = Captured()
        let runner = SummaryRunner(
            store: store, resourcesURL: resourcesURL,   // init-time dir = saventa-summary (fallback)
            claudeURL: URL(fileURLWithPath: "/usr/bin/true"),
            resolveActiveRecipe: { resolved },           // resolver returns the distinctive recipe
            runProcessOverride: { args, folder, _ in
                if let idx = args.firstIndex(of: "--append-system-prompt"), idx + 1 < args.count {
                    await captured.set(args[idx + 1])
                }
                try? "# summary".write(to: folder.appendingPathComponent("summaries/resolved.md"),
                                       atomically: true, encoding: .utf8)
                return .init(exitCode: 0, stdout: #"{"session_id":"s2"}"#)
            })

        await runner.run(meetingID: rec.id, folder: dir)
        let capturedSystemPrompt = await captured.value

        XCTAssertTrue(capturedSystemPrompt.contains("RESOLVED RECIPE CONTENT"),
                      "runner should have used the resolveActiveRecipe closure")
        XCTAssertEqual(try store.summaries(forMeeting: rec.id).first?.recipeId, "resolved")
    }

    // MARK: - Multiple summaries per meeting (T2)

    /// Stub that writes the per-recipe file under whatever `summaries/<id>.md` path the runner's prompt names,
    /// so a test doesn't have to hard-code the recipe id. Returns the given session id.
    private func writeNamedSummaryStub(session: String)
    -> (@Sendable ([String], URL, URL) async -> SummaryRunner.ProcessOutcome) {
        { args, folder, _ in
            // Extract the `summaries/<id>.md` path from the -p prompt (args[1]).
            let prompt = args.count > 1 ? args[1] : ""
            if let range = prompt.range(of: #"summaries/[^\s]+\.md"#, options: .regularExpression) {
                let rel = String(prompt[range])
                try? "# summary \(session)".write(to: folder.appendingPathComponent(rel),
                                                  atomically: true, encoding: .utf8)
            }
            return .init(exitCode: 0, stdout: "{\"session_id\":\"\(session)\"}")
        }
    }

    func testTwoDifferentRecipesProduceTwoFilesAndRowsNoOverwrite() async throws {
        let dir = try tempCopyOfGolden()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)
        let saventa = try makeTempRecipe("saventa-summary")
        let shortBrief = try makeTempRecipe("short-brief")

        let runner = SummaryRunner(
            store: store, resourcesURL: resourcesURL,
            claudeURL: URL(fileURLWithPath: "/usr/bin/true"),
            runProcessOverride: writeNamedSummaryStub(session: "s"))

        await runner.run(meetingID: rec.id, folder: dir, recipeOverride: saventa)
        await runner.run(meetingID: rec.id, folder: dir, recipeOverride: shortBrief)

        // Two distinct per-recipe files coexist (neither overwrote the other).
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("summaries/saventa-summary.md").path))
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("summaries/short-brief.md").path))
        // Two per-recipe rows.
        let rows = try store.summaries(forMeeting: rec.id)
        XCTAssertEqual(Set(rows.map(\.recipeId)), ["saventa-summary", "short-brief"])
        XCTAssertTrue(rows.allSatisfy { $0.state == "done" })
        // Rollup reflects the latest run.
        XCTAssertEqual(try store.meeting(id: rec.id)?.summaryState, "done")
    }

    /// Build a throwaway recipe dir with a distinct id (a temp dir + a `recipe.md`).
    private func makeTempRecipe(_ id: String) throws -> SummaryRecipe {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "rcp-\(id)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# \(id) recipe".write(to: root.appendingPathComponent("recipe.md"), atomically: true, encoding: .utf8)
        return SummaryRecipe(id: id, displayName: id, resourcesURL: root, isBuiltIn: false)
    }

    /// A gated stub: waits on `gate` before returning, writing the per-recipe file the prompt names.
    private func gatedStub(_ gate: Gate)
    -> (@Sendable ([String], URL, URL) async -> SummaryRunner.ProcessOutcome) {
        { args, folder, _ in
            await gate.wait()
            let prompt = args.count > 1 ? args[1] : ""
            if let range = prompt.range(of: #"summaries/[^\s]+\.md"#, options: .regularExpression) {
                try? "# x".write(to: folder.appendingPathComponent(String(prompt[range])),
                                 atomically: true, encoding: .utf8)
            }
            return .init(exitCode: 0, stdout: "{\"session_id\":\"s\"}")
        }
    }

    func testSameRecipeOnOneMeetingIsInFlightGuarded() async throws {
        let dir = try tempCopyOfGolden()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)
        let same = try makeTempRecipe("saventa-summary")

        let gate = Gate()
        let runner = SummaryRunner(
            store: store, resourcesURL: resourcesURL,
            claudeURL: URL(fileURLWithPath: "/usr/bin/true"),
            runProcessOverride: gatedStub(gate))

        // Two concurrent runs of the SAME recipe overlap; the second must be guarded out.
        async let r1: Void = runner.run(meetingID: rec.id, folder: dir, recipeOverride: same)
        async let r2: Void = runner.run(meetingID: rec.id, folder: dir, recipeOverride: same)
        try await Task.sleep(nanoseconds: 50_000_000)   // let both attempt to claim
        await gate.open()
        _ = await r1; _ = await r2

        XCTAssertEqual(try store.summaries(forMeeting: rec.id)
            .filter { $0.recipeId == "saventa-summary" }.count, 1)   // one row → no double run
    }

    func testDifferentRecipesOnOneMeetingBothRunConcurrently() async throws {
        let dir = try tempCopyOfGolden()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)
        let a = try makeTempRecipe("brief-a")
        let b = try makeTempRecipe("brief-b")

        let gate = Gate()
        let runner = SummaryRunner(
            store: store, resourcesURL: resourcesURL,
            claudeURL: URL(fileURLWithPath: "/usr/bin/true"),
            runProcessOverride: gatedStub(gate))

        // Two concurrent runs of DIFFERENT recipes overlap; both must proceed (per-recipe guard).
        async let ra: Void = runner.run(meetingID: rec.id, folder: dir, recipeOverride: a)
        async let rb: Void = runner.run(meetingID: rec.id, folder: dir, recipeOverride: b)
        try await Task.sleep(nanoseconds: 50_000_000)
        await gate.open()
        _ = await ra; _ = await rb

        let ids = Set(try store.summaries(forMeeting: rec.id).map(\.recipeId))
        XCTAssertTrue(ids.isSuperset(of: ["brief-a", "brief-b"]),
                      "different recipes on one meeting must both run (per-recipe guard)")
    }
}

/// A one-shot gate so a stubbed process can be made to overlap with another in-flight run.
private actor Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        for w in waiters { w.resume() }
        waiters.removeAll()
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
