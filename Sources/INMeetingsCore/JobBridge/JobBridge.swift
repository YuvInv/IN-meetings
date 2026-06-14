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

    /// Write the job file and start the pipeline for a finished recording.
    public func enqueue(_ result: CaptureSession.Result) {
        phase = nil
        lastError = nil
        let dir = result.directory
        let jobURL = dir.appendingPathComponent("job.json")

        var tracks: [String: String] = [:]
        if result.mic != nil { tracks["mic"] = "mic.wav" }
        if result.system != nil { tracks["system"] = "system.wav" }

        let job: [String: Any] = [
            "meeting_id": dir.lastPathComponent,
            "directory": dir.path,
            "profile": result.profile.rawValue,
            "tracks": tracks,
            "created_at": ISO8601DateFormatter().string(from: Date()),
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: job, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: jobURL, options: .atomic)
        } catch {
            lastError = "Failed to write job.json: \(error.localizedDescription)"
            captureLog.error("jobbridge.writeJob failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        spawn(jobURL: jobURL, statusURL: dir.appendingPathComponent("status.json"))
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
                    if phase == "failed" { self.lastError = obj["error"] as? String }
                    captureLog.notice("jobbridge.finished phase=\(phase, privacy: .public)")
                    timer.invalidate()
                }
            }
        }
    }
}
