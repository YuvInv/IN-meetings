import Foundation
import os

private let summaryLog = Logger(subsystem: "com.in-venture.in-meetings", category: "summary")

/// Runs a bundled or user-supplied recipe over a finished meeting package via headless `claude -p`,
/// writing `<folder>/summaries/<recipeId>.md` (ADR-008, amended; T2). A meeting can hold several
/// summaries — one per recipe — that coexist. `summary.md` is kept as a **mirror of the most-recently-
/// completed** summary for back-compat (downstream Claude skills + the pre-T3 detail/list UI).
///
/// The effective recipe is resolved per-run: a per-call `recipeOverride` (per-meeting choice) → the
/// `resolveActiveRecipe` closure (A2: reads the user's active-recipe preference off the main actor) →
/// a fallback `SummaryRecipe` derived from the init-time `resourcesURL` folder name. The recipe id
/// names both the output file and the per-(meeting, recipe) state row.
///
/// Mirrors `JobBridge`: spawn a subprocess with an explicit GUI-safe PATH, capture its log, update
/// the index (per-recipe row + the latest-run rollup), hand off the Drive re-upload, and post
/// `.summaryDidFinish`.
///
/// CRM posting is OUT — the summary is a **file only**, so the run takes no external action, needs no
/// review gate, and is safe to auto-trigger. Best-effort + non-throwing: every failure lands as
/// `failed` (on both the per-recipe row and the rollup) with a message for the dashboard's Retry button.
public final class SummaryRunner: @unchecked Sendable {
    /// The outcome of one `claude -p` invocation (the seam tests stub instead of spawning a process).
    public struct ProcessOutcome: Sendable {
        public let exitCode: Int32
        public let stdout: String
        public init(exitCode: Int32, stdout: String) { self.exitCode = exitCode; self.stdout = stdout }
    }

    private let store: MeetingStore
    /// Fallback directory holding `recipe.md` + `house-style/*.md`. Used to derive the fallback recipe
    /// (id = the folder name) when neither `resolveActiveRecipe` nor a per-run `recipeOverride` resolves.
    private let resourcesURL: URL
    /// Optional resolver called per-run to pick the active recipe. Typically reads
    /// `SummaryRecipeSettings.activeRecipeID(.standard)` from UserDefaults (off the main actor) and
    /// maps it via a `SummaryRecipeRegistry`. When nil/`nil`-returning, the `resourcesURL` fallback is used.
    private let resolveActiveRecipe: (@Sendable () -> SummaryRecipe?)?
    /// Explicit `claude` path; nil → resolve it on a GUI-safe PATH at run time.
    private let claudeURL: URL?
    /// Re-upload a summary file to Drive after a successful run (the app wires this to `DriveBackup`). The
    /// main package was already synced when the pipeline finished, so only the summary files are new. The
    /// third arg is the package-relative file name to upload (the per-recipe `summaries/<recipeId>.md`).
    private let syncSummary: (@Sendable (String, URL, String) async -> Void)?
    /// Test seam: when set, used instead of spawning a real `claude` process.
    private let runProcessOverride: (@Sendable ([String], URL, URL) async -> ProcessOutcome)?

    /// `(meeting, recipe)` pairs currently being summarized — guards a manual "Summarize" racing the
    /// auto-trigger (and keeps a single instance from double-running the same recipe on the same meeting).
    /// Keyed per-recipe so two *different* recipes on one meeting can run concurrently. `claude` usage
    /// stays gentle.
    private let lock = NSLock()
    private var inFlight: Set<String> = []

    public init(store: MeetingStore,
                resourcesURL: URL,
                claudeURL: URL? = nil,
                resolveActiveRecipe: (@Sendable () -> SummaryRecipe?)? = nil,
                syncSummary: (@Sendable (String, URL, String) async -> Void)? = nil,
                runProcessOverride: (@Sendable ([String], URL, URL) async -> ProcessOutcome)? = nil) {
        self.store = store
        self.resourcesURL = resourcesURL
        self.resolveActiveRecipe = resolveActiveRecipe
        self.claudeURL = claudeURL
        self.syncSummary = syncSummary
        self.runProcessOverride = runProcessOverride
    }

    // MARK: - Run

    /// Generate `summary.md` for a finished meeting. Safe to call on any thread; posts `.summaryDidFinish`
    /// on each state change so the dashboard reloads. A no-op if this meeting is already being summarized.
    ///
    /// - Parameters:
    ///   - recipeOverride: When non-nil, use this recipe instead of the active-recipe resolver or the
    ///     init-time fallback (per-meeting choice). Its id names the output file + the per-recipe state row.
    public func run(meetingID: String, folder: URL, recipeOverride: SummaryRecipe? = nil) async {
        // Effective recipe: per-run override → active-recipe resolver → fallback derived from `resourcesURL`.
        let recipe = recipeOverride ?? resolveActiveRecipe?() ?? Self.fallbackRecipe(resourcesURL: resourcesURL)
        let recipeId = recipe.id

        // Per-(meeting, recipe) guard: a different recipe on the same meeting may run concurrently; the same
        // recipe twice is still guarded (so a manual run can't double the auto-trigger).
        guard claimInFlight(meetingID, recipeId) else { return }
        defer { releaseInFlight(meetingID, recipeId) }

        setState(meetingID, recipeId, "running", error: nil, sessionId: nil)

        // Resolve `claude` — the only remaining per-machine dependency. Graceful if it's missing.
        guard let claude = claudeURL ?? Self.resolveClaudeURL() else {
            finishFailed(meetingID, recipeId,
                "Claude Code (`claude`) isn't installed or isn't on the PATH. Install it and sign in, then Retry.")
            return
        }

        let systemPrompt: String
        do { systemPrompt = try Self.assembleSystemPrompt(resourcesURL: recipe.resourcesURL) }
        catch {
            finishFailed(meetingID, recipeId, "Couldn't load the summary recipe: \(error.localizedDescription)")
            return
        }

        // Per-recipe output file under `summaries/` (created first so concurrent recipes never collide).
        let summariesDir = folder.appendingPathComponent("summaries")
        try? FileManager.default.createDirectory(at: summariesDir, withIntermediateDirectories: true)
        let relativeOutputPath = "summaries/\(recipeId).md"
        let actionsRelativePath = "summaries/\(recipeId)-actions.json"
        let perRecipeURL = folder.appendingPathComponent(relativeOutputPath)

        let logURL = folder.appendingPathComponent("summary.log")
        let args = Self.makeArguments(folder: folder, relativeOutputPath: relativeOutputPath,
                                      actionsOutputPath: actionsRelativePath, systemPrompt: systemPrompt)
        summaryLog.notice("summary.run meeting=\(meetingID, privacy: .public) recipe=\(recipeId, privacy: .public) claude=\(claude.path, privacy: .public)")

        let outcome: ProcessOutcome
        if let runProcessOverride {
            outcome = await runProcessOverride(args, folder, logURL)
        } else {
            outcome = await Self.spawn(claude: claude, args: args, cwd: folder, logURL: logURL)
        }

        let wroteSummary = FileManager.default.fileExists(atPath: perRecipeURL.path)
        guard outcome.exitCode == 0, wroteSummary else {
            finishFailed(meetingID, recipeId,
                         Self.failureMessage(outcome: outcome, wroteSummary: wroteSummary, relativeOutputPath: relativeOutputPath))
            return
        }

        // Mirror the just-written per-recipe file to `summary.md` (the latest completed summary) so the
        // downstream Claude skills + the pre-T3 detail/list UI keep working.
        let mirrorURL = folder.appendingPathComponent("summary.md")
        try? FileManager.default.removeItem(at: mirrorURL)
        try? FileManager.default.copyItem(at: perRecipeURL, to: mirrorURL)

        let sessionId = Self.parseSessionID(fromJSON: outcome.stdout)
        setState(meetingID, recipeId, "done", error: nil, sessionId: sessionId)
        // Sync the per-recipe file to Drive (the `summary.md` mirror also re-syncs via the full-package path
        // / textFileNames; uploading the per-recipe file keeps each recipe's summary on Drive too).
        if let syncSummary {
            await syncSummary(meetingID, folder, relativeOutputPath)
            // The structured action-items sidecar (PR 7), when the recipe emitted it, rides to Drive too.
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(actionsRelativePath).path) {
                await syncSummary(meetingID, folder, actionsRelativePath)
            }
        }
        notify()
        let recipeName = recipe.displayName
        await MainActor.run {
            MeetingNotifier.shared.post(title: "Summary ready", body: recipeName, meetingID: meetingID)
        }
        summaryLog.notice("summary.done meeting=\(meetingID, privacy: .public) recipe=\(recipeId, privacy: .public) session=\(sessionId ?? "?", privacy: .public)")
    }

    // MARK: - State + notification

    /// Update BOTH the per-(meeting, recipe) row AND the `meeting` rollup (latest run's state), so the
    /// per-recipe switcher (T3) and the existing list/pre-T3 detail view both stay correct.
    private func setState(_ id: String, _ recipeId: String, _ state: String, error: String?, sessionId: String?) {
        try? store.upsertSummary(meetingId: id, recipeId: recipeId, state: state, error: error, sessionId: sessionId)
        try? store.updateSummaryState(id: id, state: state, error: error, sessionId: sessionId)
        notify()
    }

    private func finishFailed(_ id: String, _ recipeId: String, _ message: String) {
        summaryLog.error("summary.failed meeting=\(id, privacy: .public) recipe=\(recipeId, privacy: .public): \(message, privacy: .public)")
        setState(id, recipeId, "failed", error: message, sessionId: nil)
    }

    private func notify() { NotificationCenter.default.post(name: .summaryDidFinish, object: nil) }

    private func claimInFlight(_ id: String, _ recipeId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return inFlight.insert("\(id)#\(recipeId)").inserted
    }
    private func releaseInFlight(_ id: String, _ recipeId: String) {
        lock.lock(); inFlight.remove("\(id)#\(recipeId)"); lock.unlock()
    }

    /// The fallback recipe when neither a per-run override nor the active-recipe resolver yields one: id
    /// derived from the init-time `resourcesURL` folder name (e.g. "saventa-summary"), humanized name.
    static func fallbackRecipe(resourcesURL: URL) -> SummaryRecipe {
        let id = resourcesURL.lastPathComponent
        let displayName = id.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        return SummaryRecipe(id: id, displayName: displayName, resourcesURL: resourcesURL, isBuiltIn: true)
    }

    // MARK: - Pure helpers (unit-tested)

    /// `recipe.md` + every `house-style/*.md`, concatenated with clear separators — the system prompt fed
    /// to `claude -p` via `--append-system-prompt` (we inline the house style rather than have Claude read
    /// files, so the recipe is self-contained and there's no skill install).
    ///
    /// The header is recipe-agnostic (decision 3 of A2): the recipe.md itself defines the kind of summary.
    static func assembleSystemPrompt(resourcesURL: URL) throws -> String {
        let recipe = try String(contentsOf: resourcesURL.appendingPathComponent("recipe.md"), encoding: .utf8)
        var parts = ["# IN Venture — meeting summary recipe\n\n\(recipe)"]
        let houseStyleDir = resourcesURL.appendingPathComponent("house-style")
        let files = (try? FileManager.default.contentsOfDirectory(at: houseStyleDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        for file in files {
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                parts.append("\n\n---\n\n# House style — \(file.deletingPathExtension().lastPathComponent)\n\n\(text)")
            }
        }
        return parts.joined()
    }

    /// `relativeOutputPath` is the package-relative file the run must write (T2:
    /// `summaries/<recipeId>.md`, so concurrent recipes never collide). Naming the exact path in the prompt
    /// keeps each recipe's output isolated; the rest of the flags are unchanged.
    static func makeArguments(folder: URL, relativeOutputPath: String,
                              actionsOutputPath: String, systemPrompt: String) -> [String] {
        [
            "-p",
            "Read the meeting context package in this folder (\(folder.path)) — transcript.json / transcript.txt "
                + "and metadata.json — and write the meeting summary to \(relativeOutputPath) in that same "
                + "folder, following the recipe exactly. Then write the meeting's action items / next steps as "
                + "JSON to \(actionsOutputPath) in that same folder, following the 'Action items' section of the "
                + "recipe; if there are no clear action items, write {\"items\": []}. Do not do anything else.",
            "--append-system-prompt", systemPrompt,
            "--permission-mode", "acceptEdits",
            "--allowedTools", "Read,Edit,Write,Glob,Grep",
            "--output-format", "json",
        ]
    }

    /// `claude` is installed in `~/.local/bin` (the official installer) or Homebrew; a GUI app's inherited
    /// PATH is minimal, so check the known install dirs first, then anything on the passed-in PATH.
    static func resolveClaudeURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var dirs = ["\(NSHomeDirectory())/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        if let path = environment["PATH"] { dirs += path.split(separator: ":").map(String.init) }
        for dir in dirs {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("claude")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// `claude --output-format json` prints a JSON object carrying `session_id` (+ `result`). Tolerant of
    /// JSONL / leading noise: scan lines newest-first for the first object with a `session_id`.
    static func parseSessionID(fromJSON output: String) -> String? {
        for line in output.split(separator: "\n").reversed() {
            if let data = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = obj["session_id"] as? String { return id }
        }
        if let data = output.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = obj["session_id"] as? String { return id }
        return nil
    }

    static func failureMessage(outcome: ProcessOutcome, wroteSummary: Bool, relativeOutputPath: String) -> String {
        if outcome.exitCode == 0 && !wroteSummary {
            return "Claude ran but didn't write \(relativeOutputPath) — see summary.log."
        }
        return "Summary run failed (exit \(outcome.exitCode)) — see summary.log."
    }

    // MARK: - Spawn (live path; not unit-tested — see the spec's live-verify note)

    /// Spawn `claude -p`, capturing stdout to a temp file (read after exit — no pipe-buffer deadlock, no
    /// cross-thread data race) and stderr to `summary.log`. Returns the exit code + the captured stdout.
    static func spawn(claude: URL, args: [String], cwd: URL, logURL: URL) async -> ProcessOutcome {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = claude
            process.arguments = args
            process.currentDirectoryURL = cwd

            var env = ProcessInfo.processInfo.environment
            // A Finder-launched GUI app has a minimal PATH; ensure `claude` (and the node it shells to) are
            // findable. `claude` inherits the user's auth/config from the home dir.
            let prefix = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["PATH"] = prefix + ":" + (env["PATH"] ?? "")
            process.environment = env

            let outURL = cwd.appendingPathComponent(".summary.stdout.json")
            FileManager.default.createFile(atPath: outURL.path, contents: nil)
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let outHandle = try? FileHandle(forWritingTo: outURL)
            let logHandle = try? FileHandle(forWritingTo: logURL)
            if let outHandle { process.standardOutput = outHandle }
            if let logHandle { process.standardError = logHandle }

            process.terminationHandler = { proc in
                try? outHandle?.close()
                let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
                // Tee stdout into the durable log too, then drop the temp file.
                if let data = stdout.data(using: .utf8), let log = try? FileHandle(forWritingTo: logURL) {
                    try? log.seekToEnd(); try? log.write(contentsOf: data); try? log.close()
                }
                try? logHandle?.close()
                try? FileManager.default.removeItem(at: outURL)
                continuation.resume(returning: ProcessOutcome(exitCode: proc.terminationStatus, stdout: stdout))
            }
            do { try process.run() }
            catch {
                try? outHandle?.close(); try? logHandle?.close()
                try? FileManager.default.removeItem(at: outURL)
                continuation.resume(returning: ProcessOutcome(
                    exitCode: -1, stdout: "spawn failed: \(error.localizedDescription)"))
            }
        }
    }
}

public extension Notification.Name {
    /// Posted when a `SummaryRunner` run changes state (running → done / failed). The dashboard observes it
    /// to refresh the Summary panel without a manual reload (same pattern as `.jobBridgeDidFinish`).
    static let summaryDidFinish = Notification.Name("INMeetings.summaryDidFinish")
}
