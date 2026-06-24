import Foundation
import os

private let dictationLog = Logger(subsystem: "com.in-venture.in-meetings", category: "dictation")

/// Transcribes a short mic clip on-device by calling `whisper-cli` **directly** — bypassing the Python
/// pipeline (which diarizes/packages and is serialized behind meeting jobs) for low dictation latency
/// (A6, decision 1). The dedicated path runs no VAD/diarize/package: one WAV in, trimmed text out.
///
/// Mirrors `SummaryRunner`: pure, unit-tested argument building + an injectable process seam
/// (`runProcessOverride`) so the success/failure paths are tested without spawning a real `whisper-cli`.
/// The live spawn reuses the GUI-safe-PATH approach (a Finder-launched app has a minimal PATH).
public struct WhisperCliTranscriber: DictationController.Transcribing, Sendable {
    /// The outcome of one `whisper-cli` invocation (the seam tests stub instead of spawning a process).
    public struct ProcessOutcome: Sendable {
        public let exitCode: Int32
        public let stdout: String
        public init(exitCode: Int32, stdout: String) { self.exitCode = exitCode; self.stdout = stdout }
    }

    public enum TranscribeError: Error, Sendable {
        /// `whisper-cli` couldn't be found in the known dirs or on PATH.
        case whisperNotFound
        /// `whisper-cli` exited non-zero.
        case processFailed(exitCode: Int32, stdout: String)
        /// The process ran but no `<base>.txt` was produced (or it was empty after trimming).
        case noOutput
    }

    /// The installed Hebrew GGML model (same one the pipeline uses). whisper.cpp transcribes other
    /// languages with it too — `-l <lang>` selects Hebrew vs. English at runtime.
    private let model: URL
    /// Explicit `whisper-cli` path; nil → resolve it on a GUI-safe PATH at run time.
    private let whisperCliURL: URL?
    /// Test seam: when set, used instead of spawning a real `whisper-cli`. Receives the built args, the
    /// out-base URL (where to write `<base>.txt`), and returns the process outcome.
    private let runProcessOverride: (@Sendable ([String], URL) async -> ProcessOutcome)?

    public init(model: URL,
                whisperCliURL: URL? = nil,
                runProcessOverride: (@Sendable ([String], URL) async -> ProcessOutcome)? = nil) {
        self.model = model
        self.whisperCliURL = whisperCliURL
        self.runProcessOverride = runProcessOverride
    }

    // MARK: - Pure helpers (unit-tested)

    /// Build the `whisper-cli` invocation for dictation: text output only (lower latency, simplest), no
    /// VAD/JSON. Writes `<outBase>.txt`. Mirrors `pipeline/.../asr.py:whisper_cmd` but `-otxt` instead of
    /// `-oj`. `args[0]` is the resolved executable path.
    public static func arguments(whisperCli: URL, model: URL, wav: URL, outBase: URL, language: String) -> [String] {
        [whisperCli.path,
         "-m", model.path,
         "-f", wav.path,
         "-l", language,
         "-bs", "5",
         "-otxt",
         "-of", outBase.path]
    }

    /// `whisper-cli` is installed by Homebrew (`whisper-cpp` formula); a GUI app's inherited PATH is
    /// minimal, so check the known install dirs first, then anything on the passed-in PATH (mirrors
    /// `SummaryRunner.resolveClaudeURL`).
    public static func resolveWhisperCliURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        if let path = environment["PATH"] { dirs += path.split(separator: ":").map(String.init) }
        for dir in dirs {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("whisper-cli")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Read + trim the `<base>.txt` whisper.cpp writes. Returns nil when the file is missing or blank.
    public static func parseTranscript(at txtURL: URL) -> String? {
        guard let raw = try? String(contentsOf: txtURL, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Transcribe

    /// Transcribe `wav` in `language` ("he"/"en"); returns the trimmed text or an error. Resolves
    /// `whisper-cli`, builds the args, runs the process (seam or live spawn), then reads `<base>.txt`.
    public func transcribe(wav: URL, language: String) async -> Result<String, Error> {
        guard let whisperCli = whisperCliURL ?? Self.resolveWhisperCliURL() else {
            dictationLog.error("dictation.transcribe whisper-cli not found")
            return .failure(TranscribeError.whisperNotFound)
        }

        // Out-base sits next to the WAV (a private temp dir owned by the caller); whisper appends `.txt`.
        let outBase = wav.deletingPathExtension()
        let txtURL = outBase.appendingPathExtension("txt")
        try? FileManager.default.removeItem(at: txtURL)   // never read a stale transcript

        let args = Self.arguments(whisperCli: whisperCli, model: model, wav: wav, outBase: outBase,
                                  language: language)
        dictationLog.notice("dictation.transcribe lang=\(language, privacy: .public) whisper=\(whisperCli.path, privacy: .public)")

        let outcome: ProcessOutcome
        if let runProcessOverride {
            outcome = await runProcessOverride(args, outBase)
        } else {
            outcome = await Self.spawn(executable: whisperCli, args: Array(args.dropFirst()))
        }

        guard outcome.exitCode == 0 else {
            dictationLog.error("dictation.transcribe failed exit=\(outcome.exitCode, privacy: .public)")
            return .failure(TranscribeError.processFailed(exitCode: outcome.exitCode, stdout: outcome.stdout))
        }
        guard let text = Self.parseTranscript(at: txtURL) else {
            return .failure(TranscribeError.noOutput)
        }
        dictationLog.notice("dictation.transcribe ok chars=\(text.count, privacy: .public)")
        return .success(text)
    }

    // MARK: - Spawn (live path; not unit-tested — see the spec's live-verify note)

    /// Hard ceiling on a single `whisper-cli` dictation run. A wedged/looping process would otherwise
    /// leave the awaiting `Task` (and the dictation FSM) stuck in `.transcribing` forever; on timeout we
    /// terminate the process so the run finishes as a failure. Dictation clips are short, so 30s is a
    /// generous bound for a healthy transcribe.
    static let spawnTimeout: Duration = .seconds(30)

    /// Spawn `whisper-cli`, capturing stdout/stderr to a temp file (read after exit — no pipe-buffer
    /// deadlock). Reuses the GUI-safe-PATH approach from `JobBridge`/`SummaryRunner`. Returns the exit
    /// code + the captured stdout (the transcript itself is read from `<base>.txt`, not stdout).
    ///
    /// A watchdog terminates the process after `spawnTimeout`; the termination fires the existing
    /// `terminationHandler`, which is the *single* place that resumes the continuation. A lock-guarded
    /// "resumed" flag makes the resume happen exactly once even though three paths can reach it
    /// (normal exit, the `run()` catch, and a watchdog that loses the race) — guaranteeing no
    /// double-resume (which would crash) and no leak.
    static func spawn(executable: URL, args: [String], timeout: Duration = spawnTimeout) async -> ProcessOutcome {
        // Guard so the continuation is resumed exactly once across the termination, catch, and watchdog
        // paths. The watchdog only ever calls `process.terminate()`, never resumes directly.
        let resumeLock = NSLock()
        nonisolated(unsafe) var didResume = false
        @Sendable func resumeOnce(_ continuation: CheckedContinuation<ProcessOutcome, Never>,
                                  _ outcome: ProcessOutcome) {
            resumeLock.lock()
            let shouldResume = !didResume
            didResume = true
            resumeLock.unlock()
            if shouldResume { continuation.resume(returning: outcome) }
        }

        let process = Process()
        // Watchdog: fire-and-forget terminate after `timeout`; cancelled once the process exits.
        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            if Task.isCancelled { return }
            if process.isRunning { process.terminate() }
        }
        defer { watchdog.cancel() }

        return await withCheckedContinuation { continuation in
            process.executableURL = executable
            process.arguments = args

            var env = ProcessInfo.processInfo.environment
            let prefix = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["PATH"] = prefix + ":" + (env["PATH"] ?? "")
            process.environment = env

            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dictation-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: outURL.path, contents: nil)
            let outHandle = try? FileHandle(forWritingTo: outURL)
            if let outHandle {
                process.standardOutput = outHandle
                process.standardError = outHandle
            }

            process.terminationHandler = { proc in
                watchdog.cancel()
                try? outHandle?.close()
                let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(at: outURL)
                // A watchdog-terminated process exits non-zero (signal), so this maps to a failure
                // outcome via the existing exit-code check in `transcribe`.
                resumeOnce(continuation, ProcessOutcome(exitCode: proc.terminationStatus, stdout: stdout))
            }
            do { try process.run() }
            catch {
                watchdog.cancel()
                try? outHandle?.close()
                try? FileManager.default.removeItem(at: outURL)
                resumeOnce(continuation, ProcessOutcome(
                    exitCode: -1, stdout: "spawn failed: \(error.localizedDescription)"))
            }
        }
    }
}
