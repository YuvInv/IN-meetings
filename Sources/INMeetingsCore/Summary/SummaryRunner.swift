import Foundation
import os

private let summaryLog = Logger(subsystem: "com.in-venture.in-meetings", category: "summary")

/// Runs IN Venture's bundled `saventa-summary` recipe over a finished meeting package via headless
/// `claude -p`, writing `<folder>/summary.md` (ADR-008, amended: an app-bundled recipe, **not** a
/// globally-installed skill). Mirrors `JobBridge`: spawn a subprocess with an explicit GUI-safe PATH,
/// capture its log, update the index, hand off the Drive re-upload, and post `.summaryDidFinish`.
///
/// CRM posting is OUT — the summary is a **file only**, so the run takes no external action, needs no
/// review gate, and is safe to auto-trigger. Best-effort + non-throwing: every failure lands as
/// `summaryState = "failed"` with a message for the dashboard's Retry button.
public final class SummaryRunner: @unchecked Sendable {
    /// The outcome of one `claude -p` invocation (the seam tests stub instead of spawning a process).
    public struct ProcessOutcome: Sendable {
        public let exitCode: Int32
        public let stdout: String
        public init(exitCode: Int32, stdout: String) { self.exitCode = exitCode; self.stdout = stdout }
    }

    private let store: MeetingStore
    /// Directory holding `recipe.md` + `house-style/*.md` (the app bundle's `skills/saventa-summary`).
    private let resourcesURL: URL
    /// Explicit `claude` path; nil → resolve it on a GUI-safe PATH at run time.
    private let claudeURL: URL?
    /// Re-upload `summary.md` to Drive after a successful run (the app wires this to `DriveBackup`). The
    /// main package was already synced when the pipeline finished, so only `summary.md` is new.
    private let syncSummary: (@Sendable (String, URL) async -> Void)?
    /// Test seam: when set, used instead of spawning a real `claude` process.
    private let runProcessOverride: (@Sendable ([String], URL, URL) async -> ProcessOutcome)?

    /// Meetings currently being summarized — guards a manual "Summarize" racing the auto-trigger (and
    /// keeps a single instance from double-running the same meeting). `claude` usage stays gentle.
    private let lock = NSLock()
    private var inFlight: Set<String> = []

    public init(store: MeetingStore,
                resourcesURL: URL,
                claudeURL: URL? = nil,
                syncSummary: (@Sendable (String, URL) async -> Void)? = nil,
                runProcessOverride: (@Sendable ([String], URL, URL) async -> ProcessOutcome)? = nil) {
        self.store = store
        self.resourcesURL = resourcesURL
        self.claudeURL = claudeURL
        self.syncSummary = syncSummary
        self.runProcessOverride = runProcessOverride
    }

    // MARK: - Run

    /// Generate `summary.md` for a finished meeting. Safe to call on any thread; posts `.summaryDidFinish`
    /// on each state change so the dashboard reloads. A no-op if this meeting is already being summarized.
    public func run(meetingID: String, folder: URL) async {
        guard claimInFlight(meetingID) else { return }
        defer { releaseInFlight(meetingID) }

        setState(meetingID, "running", error: nil, sessionId: nil)

        // Resolve `claude` — the only remaining per-machine dependency. Graceful if it's missing.
        guard let claude = claudeURL ?? Self.resolveClaudeURL() else {
            finishFailed(meetingID,
                "Claude Code (`claude`) isn't installed or isn't on the PATH. Install it and sign in, then Retry.")
            return
        }

        let systemPrompt: String
        do { systemPrompt = try Self.assembleSystemPrompt(resourcesURL: resourcesURL) }
        catch {
            finishFailed(meetingID, "Couldn't load the bundled summary recipe: \(error.localizedDescription)")
            return
        }

        let logURL = folder.appendingPathComponent("summary.log")
        let args = Self.makeArguments(folder: folder, systemPrompt: systemPrompt)
        summaryLog.notice("summary.run meeting=\(meetingID, privacy: .public) claude=\(claude.path, privacy: .public)")

        let outcome: ProcessOutcome
        if let runProcessOverride {
            outcome = await runProcessOverride(args, folder, logURL)
        } else {
            outcome = await Self.spawn(claude: claude, args: args, cwd: folder, logURL: logURL)
        }

        let summaryURL = folder.appendingPathComponent("summary.md")
        let wroteSummary = FileManager.default.fileExists(atPath: summaryURL.path)
        guard outcome.exitCode == 0, wroteSummary else {
            finishFailed(meetingID, Self.failureMessage(outcome: outcome, wroteSummary: wroteSummary))
            return
        }

        let sessionId = Self.parseSessionID(fromJSON: outcome.stdout)
        setState(meetingID, "done", error: nil, sessionId: sessionId)
        if let syncSummary { await syncSummary(meetingID, folder) }
        notify()
        summaryLog.notice("summary.done meeting=\(meetingID, privacy: .public) session=\(sessionId ?? "?", privacy: .public)")
    }

    // MARK: - State + notification

    private func setState(_ id: String, _ state: String, error: String?, sessionId: String?) {
        try? store.updateSummaryState(id: id, state: state, error: error, sessionId: sessionId)
        notify()
    }

    private func finishFailed(_ id: String, _ message: String) {
        summaryLog.error("summary.failed meeting=\(id, privacy: .public): \(message, privacy: .public)")
        setState(id, "failed", error: message, sessionId: nil)
    }

    private func notify() { NotificationCenter.default.post(name: .summaryDidFinish, object: nil) }

    private func claimInFlight(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return inFlight.insert(id).inserted
    }
    private func releaseInFlight(_ id: String) {
        lock.lock(); inFlight.remove(id); lock.unlock()
    }

    // MARK: - Pure helpers (unit-tested)

    /// `recipe.md` + every `house-style/*.md`, concatenated with clear separators — the system prompt fed
    /// to `claude -p` via `--append-system-prompt` (we inline the house style rather than have Claude read
    /// files, so the recipe is self-contained and there's no skill install).
    static func assembleSystemPrompt(resourcesURL: URL) throws -> String {
        let recipe = try String(contentsOf: resourcesURL.appendingPathComponent("recipe.md"), encoding: .utf8)
        var parts = ["# IN Venture — Saventa summary recipe\n\n\(recipe)"]
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

    static func makeArguments(folder: URL, systemPrompt: String) -> [String] {
        [
            "-p",
            "Read the meeting context package in this folder (\(folder.path)) — transcript.json / transcript.txt "
                + "and metadata.json — and write IN Venture's Saventa deal summary to summary.md in that same "
                + "folder, following the recipe exactly. Do not do anything else.",
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

    static func failureMessage(outcome: ProcessOutcome, wroteSummary: Bool) -> String {
        if outcome.exitCode == 0 && !wroteSummary {
            return "Claude ran but didn't write summary.md — see summary.log."
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
