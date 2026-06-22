import Foundation
import Observation

/// Bridges the Swift app to the Python pipeline over files (ADR-009).
///
/// On Stop we write `job.json` into the meeting folder, spawn `python -m in_meetings_pipeline run <job>`,
/// and poll `status.json` for the phase. Paths default to the dev layout and are overridable via
/// `IN_MEETINGS_PIPELINE_DIR` / `IN_MEETINGS_PYTHON` (Phase 5 will bundle the pipeline + a pinned env).
@available(macOS 14.2, *)
@MainActor
@Observable
public final class JobBridge {
    /// queued | transcribing | diarizing | packaging | done | failed  (nil = no job yet)
    public private(set) var phase: String?
    public private(set) var lastError: String?

    private let pipelineDir: URL
    private let python: URL
    private var watch: Timer?
    private var process: Process?
    /// The SQLite index (ADR-006). Opened lazily on first completion so tests that never finish a job
    /// don't touch Application Support; a failure to open is non-fatal (indexing is best-effort).
    /// `@ObservationIgnored` keeps the `@Observable` macro from making it computed (lazy needs storage).
    @ObservationIgnored private lazy var store: MeetingStore? = try? MeetingStore(url: MeetingStore.defaultURL)
    /// Write-through Drive backup (slice 6), over the same store. No-op until the user connects an
    /// account + picks a location, so it costs nothing when Drive isn't set up.
    @ObservationIgnored private lazy var driveBackup: DriveBackup? = store.map { DriveBackup(meetingStore: $0) }
    /// Phase-2 calendar context (ADR-004): fetched before spawn so the assembler has its input. No-op
    /// until the user connects a Google account (the same credential as Drive).
    @ObservationIgnored private lazy var calendarContext: CalendarContext? = CalendarContext()
    /// Saventa-summary auto-trigger (ADR-008, amended): runs the app-bundled recipe via headless `claude -p`
    /// after a finished call, writing summary.md + syncing it to Drive. nil when the recipe isn't bundled
    /// (e.g. unit tests) → auto-summary no-ops. Shares the store; re-uploads summary.md via `driveBackup`.
    @ObservationIgnored private lazy var summaryRunner: SummaryRunner? = {
        guard let store, let resources = Self.bundledSummaryResourcesURL() else { return nil }
        let backup = driveBackup
        return SummaryRunner(
            store: store, resourcesURL: resources,
            syncSummary: backup.map { b in
                { @Sendable (id: String, folder: URL) in
                    await b.syncSummaryIfConfigured(meetingID: id, packageFolder: folder)
                }
            })
    }()

    public init(pipelineDir: URL = JobBridge.defaultPipelineDir, python: URL = JobBridge.defaultPython) {
        self.pipelineDir = pipelineDir
        self.python = python
    }

    public nonisolated static var defaultPipelineDir: URL {
        if let env = ProcessInfo.processInfo.environment["IN_MEETINGS_PIPELINE_DIR"] {
            return URL(fileURLWithPath: env)
        }
        return URL(fileURLWithPath: "/Users/yuvalnaor/repos/IN-meetings/pipeline")
    }

    public nonisolated static var defaultPython: URL {
        if let env = ProcessInfo.processInfo.environment["IN_MEETINGS_PYTHON"] {
            return URL(fileURLWithPath: env)
        }
        // The pipeline's pinned venv (Python 3.11 + senko, which requires <3.14 — system python3 is
        // 3.14 and can't import it). Phase 5 bundles a sealed env; until then this is the dev venv.
        return defaultPipelineDir.appendingPathComponent(".venv/bin/python")
    }

    /// The bundled saventa-summary recipe dir (`Resources/skills/saventa-summary` — recipe.md + house-style).
    /// nil when not bundled (e.g. unit tests, where `Bundle.main` is the test runner) → auto-summary no-ops.
    nonisolated static func bundledSummaryResourcesURL() -> URL? {
        if let recipe = Bundle.main.url(forResource: "recipe", withExtension: "md",
                                        subdirectory: "skills/saventa-summary") {
            return recipe.deletingLastPathComponent()
        }
        if let res = Bundle.main.resourceURL {
            let dir = res.appendingPathComponent("skills/saventa-summary")
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("recipe.md").path) { return dir }
        }
        return nil
    }

    /// Write the job file and start the pipeline for a finished recording.
    /// Write the job file and start the pipeline for a finished recording. The record-time facts
    /// (`startedAt` / `endedAt` / `captureSourceApp`) feed metadata.json (ADR-005); sample rate +
    /// durations are read from the WAVs by the pipeline, and video defaults off (V1) — so neither is
    /// sent here.
    public func enqueue(_ result: CaptureSession.Result,
                        startedAt: Date = Date(), endedAt: Date = Date(),
                        captureSourceApp: String? = nil) {
        phase = nil
        lastError = nil
        let dir = result.directory
        let jobURL = dir.appendingPathComponent("job.json")

        let job = Self.makeJob(result, startedAt: startedAt, endedAt: endedAt,
                               captureSourceApp: captureSourceApp)
        do {
            let data = try JSONSerialization.data(withJSONObject: job, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: jobURL, options: .atomic)
        } catch {
            lastError = "Failed to write job.json: \(error.localizedDescription)"
            phase = "failed"
            captureLog.error("jobbridge.writeJob failed: \(error.localizedDescription, privacy: .public)")
            recordFailure(folder: dir, error: lastError)
            return
        }
        let statusURL = dir.appendingPathComponent("status.json")
        phase = "queued"
        // Fetch calendar context (best-effort, short timeout) *before* spawning so the assembler has its
        // context.input.json; then start the pipeline. A no-op when no Google account is connected.
        Task { @MainActor in
            await self.calendarContext?.writeInput(into: dir, startedAt: startedAt, endedAt: endedAt,
                                                   captureSourceApp: captureSourceApp)
            self.spawn(jobURL: jobURL, statusURL: statusURL)
        }
    }

    /// Start the pipeline for an *imported* recording. The folder must already contain the normalized
    /// audio track (`audioFilename`) and — for the event-bound path — a pinned `context.input.json`
    /// (written by the import coordinator). Unlike `enqueue`, this does NOT fetch live calendar context.
    public func enqueueImport(directory: URL, audioFilename: String, startedAt: Date, endedAt: Date) {
        phase = nil
        lastError = nil
        let jobURL = directory.appendingPathComponent("job.json")
        let job = ImportJob.make(meetingId: directory.lastPathComponent, directory: directory,
                                 audioFilename: audioFilename, startedAt: startedAt, endedAt: endedAt)
        do {
            let data = try JSONSerialization.data(withJSONObject: job, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: jobURL, options: .atomic)
        } catch {
            lastError = "Failed to write job.json: \(error.localizedDescription)"
            phase = "failed"
            captureLog.error("jobbridge.import.writeJob failed: \(error.localizedDescription, privacy: .public)")
            recordFailure(folder: directory, error: lastError)
            return
        }
        let statusURL = directory.appendingPathComponent("status.json")
        phase = "queued"
        spawn(jobURL: jobURL, statusURL: statusURL)
    }

    /// The Swift→Python job contract (ADR-009), kept pure (`nonisolated`) for testability off the main
    /// actor. Keys mirror `pipeline/job.py`.
    nonisolated static func makeJob(_ result: CaptureSession.Result,
                                    startedAt: Date, endedAt: Date,
                                    captureSourceApp: String?) -> [String: Any] {
        var tracks: [String: String] = [:]
        if result.mic != nil { tracks["mic"] = "mic.wav" }
        if result.system != nil { tracks["system"] = "system.wav" }

        let iso = ISO8601DateFormatter()
        var job: [String: Any] = [
            "meeting_id": result.directory.lastPathComponent,
            "directory": result.directory.path,
            "profile": result.profile.rawValue,
            "tracks": tracks,
            "started_at": iso.string(from: startedAt),
            "ended_at": iso.string(from: endedAt),
            "created_at": iso.string(from: endedAt),
            "video": result.video != nil,   // a call-window video.mov was captured (V1) → metadata.json
        ]
        if let captureSourceApp { job["capture_source_app"] = captureSourceApp }
        return job
    }

    private func spawn(jobURL: URL, statusURL: URL) {
        let process = Process()
        process.executableURL = python
        process.arguments = ["-m", "in_meetings_pipeline", "run", jobURL.path]
        process.currentDirectoryURL = pipelineDir
        // A GUI app launched from Finder has a minimal PATH; give the pipeline what it needs to find
        // whisper-cli (slice 4b) and friends.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        // Point the pipeline at the app-managed model once ModelManager has downloaded + verified it
        // (Harvest 1). Until the file exists, leave IN_MEETINGS_MODEL unset so asr.py falls back to its
        // benchmark copy (so a dev box with the benchmark model still transcribes pre-download).
        let model = ModelManager.installedModelURL
        if FileManager.default.fileExists(atPath: model.path) {
            env["IN_MEETINGS_MODEL"] = model.path
        }
        // Silero VAD (also app-managed): when present the pipeline runs whisper with --vad so silent
        // stretches aren't hallucinated into text. Absent → pipeline falls back to is_silent gating only.
        let vad = ModelManager.installedVadURL
        if FileManager.default.fileExists(atPath: vad.path) {
            env["IN_MEETINGS_VAD_MODEL"] = vad.path
        }
        process.environment = env

        // Capture the pipeline's stdout+stderr into a per-meeting log — the durable trail for
        // reviewing diarization/ASR on real meetings. The multi-party-call diarization quality check
        // is deferred to live calls (DECISIONS 2026-06-11 slice 4c); this is what makes it reviewable.
        let logURL = jobURL.deletingLastPathComponent().appendingPathComponent("pipeline.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let logHandle = try? FileHandle(forWritingTo: logURL) {
            process.standardOutput = logHandle
            process.standardError = logHandle
        }
        do {
            try process.run()
        } catch {
            lastError = "Failed to start pipeline: \(error.localizedDescription)"
            phase = "failed"
            captureLog.error("jobbridge.spawn failed: \(error.localizedDescription, privacy: .public)")
            recordFailure(folder: jobURL.deletingLastPathComponent(), error: lastError)
            return
        }
        self.process = process
        phase = "queued"
        captureLog.notice("jobbridge.spawned meeting=\(jobURL.deletingLastPathComponent().lastPathComponent, privacy: .public)")
        watchStatus(statusURL)
    }

    private func watchStatus(_ statusURL: URL) {
        watch?.invalidate()
        watch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                guard let data = try? Data(contentsOf: statusURL),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let phase = obj["phase"] as? String else { return }
                self.phase = phase
                if phase == "done" || phase == "failed" {
                    let folder = statusURL.deletingLastPathComponent()
                    if phase == "failed" {
                        self.lastError = obj["error"] as? String
                        self.recordFailure(folder: folder, error: obj["error"] as? String)
                    }
                    if phase == "done" {
                        self.indexCompletedPackage(at: folder)
                        self.notifyDashboard()
                    }
                    captureLog.notice("jobbridge.finished phase=\(phase, privacy: .public)")
                    timer.invalidate()
                }
            }
        }
    }

    /// Mirror a finished package into the SQLite index (ADR-006) so the dashboard can see it.
    /// Best-effort + idempotent: an index failure must not break the recording flow (the on-disk
    /// package is the durable source of truth, and re-indexing the same id just updates the row).
    private func indexCompletedPackage(at folder: URL) {
        var meetingType: String?
        do {
            let record = try store?.indexPackage(at: folder)
            meetingType = record?.type
            captureLog.notice("jobbridge.indexed meeting=\(record?.id ?? "?", privacy: .public)")
        } catch {
            captureLog.error("jobbridge.index failed: \(error.localizedDescription, privacy: .public)")
        }
        let id = folder.lastPathComponent
        // Auto-summarize finished *calls* when the toggle is on (file-only → safe to auto-run). In-person
        // meetings can still be summarized manually from the dashboard.
        let autoSummarize = meetingType == "call"
            && CaptureSettings.bool(.standard, CaptureSettings.Keys.autoSummary, default: true)
        // Write-through to Drive, *then* (for calls, if enabled) auto-summarize — sequenced in one task so
        // the summary.md re-upload finds the Drive folder id the package sync just set. Both are
        // best-effort + no-ops when unconfigured.
        let backup = driveBackup
        let runner = autoSummarize ? summaryRunner : nil
        Task {
            if let backup { await backup.syncIfConfigured(meetingID: id, packageFolder: folder) }
            if let runner { await runner.run(meetingID: id, folder: folder) }
        }
    }

    /// Kick the saventa-summary run for a meeting — the dashboard's manual **Summarize** / **Retry** button
    /// (the auto path above runs the same `SummaryRunner`, so runs stay serialized). Non-blocking; a no-op
    /// if the recipe isn't bundled. The runner updates the index, posts `.summaryDidFinish`, and re-uploads
    /// summary.md to Drive on success.
    public func summarize(meetingID: String, folder: URL) {
        guard let summaryRunner else { return }
        Task { await summaryRunner.run(meetingID: meetingID, folder: folder) }
    }

    /// Record a pipeline failure in the index (reliability pass) so the dashboard can show it instead of
    /// leaving the meeting stuck looking like it's still processing. Best-effort + idempotent.
    private func recordFailure(folder: URL, error: String?) {
        do { _ = try store?.markFailed(folder: folder, error: error) }
        catch { captureLog.error("jobbridge.markFailed failed: \(error.localizedDescription, privacy: .public)") }
        notifyDashboard()
    }

    /// Tell any open dashboard to reload its index (a finished/failed meeting just changed the DB).
    private func notifyDashboard() {
        NotificationCenter.default.post(name: .jobBridgeDidFinish, object: nil)
    }
}

public extension Notification.Name {
    /// Posted on the main thread when a pipeline job reaches a terminal phase (done or failed). The
    /// dashboard observes this and reloads its index so finished and failed meetings appear without the
    /// user having to reopen the window.
    static let jobBridgeDidFinish = Notification.Name("INMeetings.jobBridgeDidFinish")
}
