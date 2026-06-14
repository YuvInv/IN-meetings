// Adapted from Mila (https://github.com/island-io/mila), © Island Technology, Inc. / Uri Harduf,
// Apache-2.0. Changes: rewritten for IN-meetings' @Observable/@MainActor model (Mila used Combine
// @Published); reduced to a single model; dropped the CoreML encoder download (the Homebrew
// whisper-cli is built without CoreML, so a sibling .mlmodelc is inert — re-enable with a Phase-5
// WHISPER_COREML build, ADR-009); the installed model feeds the Python pipeline via IN_MEETINGS_MODEL,
// not Swift whisper bindings. See THIRD_PARTY_NOTICES.md.

import CryptoKit
import Foundation
import Observation
import os

private let modelLog = Logger(subsystem: "com.in-venture.in-meetings", category: "models")

/// Downloads + verifies the on-device ASR model on first launch, so a teammate can install the app
/// without hand-placing a 1.6 GB GGML file. The verified model lives under Application Support and is
/// handed to the Python pipeline via the `IN_MEETINGS_MODEL` env var (set in `JobBridge.spawn`).
///
/// Flow: `ensureReady()` → fast-path to `.ready` if the file is already present at the expected size →
/// otherwise download to a `.partial` temp, stream-hash it (1 MiB chunks), and only swap it into place
/// if the SHA-256 matches the pinned value. A corrupt or swapped download never reaches whisper.cpp.
@available(macOS 14.2, *)
@MainActor
@Observable
public final class ModelManager {
    public enum Phase: Sendable {
        case absent
        case downloading(progress: Double)
        case verifying
        case ready
        case failed(String)
    }

    public private(set) var phase: Phase = .absent

    /// True once the model is present and verified.
    public var isReady: Bool { if case .ready = phase { return true } else { return false } }

    /// One-line status for the menu, or nil when ready (nothing to show).
    public var statusText: String? {
        switch phase {
        case .absent:             return "Model: preparing…"
        case .downloading(let p): return "Model: downloading \(Int((p * 100).rounded()))%…"
        case .verifying:          return "Model: verifying…"
        case .ready:              return nil
        case .failed(let msg):    return "Model error — \(msg)"
        }
    }

    private nonisolated let entry: ModelCatalog.Entry
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var session: URLSession?

    public init(entry: ModelCatalog.Entry = ModelCatalog.hebrewTurbo) {
        self.entry = entry
    }

    // MARK: - Paths

    /// `~/Library/Application Support/IN Meetings/Models/` — sibling of the Recordings cache.
    public nonisolated static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("IN Meetings/Models", isDirectory: true)
    }

    /// Absolute path of the installed Hebrew model. `JobBridge` points the pipeline here via
    /// `IN_MEETINGS_MODEL` when the file exists.
    public nonisolated static var installedModelURL: URL {
        modelsDirectory.appendingPathComponent(ModelCatalog.hebrewTurbo.filename)
    }

    private nonisolated var destination: URL {
        Self.modelsDirectory.appendingPathComponent(entry.filename)
    }

    // MARK: - Lifecycle

    /// Idempotent: ready immediately if the file is already installed (size match), else kick off the
    /// background download. Safe to call repeatedly; only the first call starts a download.
    public func ensureReady() {
        guard !didStart else { return }
        didStart = true

        if isInstalled() {
            phase = .ready
            modelLog.notice("model already installed: \(self.destination.path, privacy: .public)")
            return
        }
        startDownload()
    }

    /// Re-arm after a failure (menu "Retry Model Download").
    public func retry() {
        guard case .failed = phase else { return }
        didStart = false
        phase = .absent
        ensureReady()
    }

    /// Cheap launch check — present and the right size. The full SHA verification runs once, right
    /// after our own download; re-hashing 1.6 GB on every launch would be wasteful, and a size
    /// mismatch already catches the common interrupted-download case.
    private func isInstalled() -> Bool {
        guard let size = try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int
        else { return false }
        return size == entry.sizeBytes
    }

    private func startDownload() {
        phase = .downloading(progress: 0)
        modelLog.notice("downloading model from \(self.entry.url.absoluteString, privacy: .public)")
        let delegate = DownloadDelegate(owner: self, entry: entry, destination: destination)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 2 * 60 * 60   // big file, possibly slow links
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        session.downloadTask(with: entry.url).resume()
    }

    /// Called by the download delegate (already hopped to the main actor). Terminal phases tear the
    /// session down so it (and its delegate) are released.
    fileprivate func apply(_ next: Phase) {
        phase = next
        switch next {
        case .ready, .failed:
            session?.finishTasksAndInvalidate()
            session = nil
        default:
            break
        }
    }

    // MARK: - Hashing (shared with the delegate + tests)

    /// Streaming SHA-256 of a file in 1 MiB chunks — never loads the whole multi-GB file into memory.
    nonisolated static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// URLSession delegate kept separate from `ModelManager` so the manager stays a clean `@Observable`
/// (URLSession requires an `NSObject` delegate). Holds the owner weakly — the manager owns the session,
/// not vice-versa — so there is no retain cycle.
@available(macOS 14.2, *)
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    // Strong reference: the manager owns the session which owns this delegate which owns the manager —
    // a deliberate cycle broken on the terminal phase (`ModelManager.apply` nils + invalidates the
    // session). `@unchecked Sendable` is sound because `entry`/`destination` are immutable Sendable
    // values and `owner` is only ever touched inside the `@MainActor` Task hops below.
    private let owner: ModelManager
    private let entry: ModelCatalog.Entry
    private let destination: URL

    init(owner: ModelManager, entry: ModelCatalog.Entry, destination: URL) {
        self.owner = owner
        self.entry = entry
        self.destination = destination
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(entry.sizeBytes)
        let progress = total > 0 ? min(max(Double(totalBytesWritten) / Double(total), 0), 1) : 0
        Task { @MainActor in owner.apply(.downloading(progress: progress)) }
    }

    /// `location` is deleted as soon as this method returns, so the move + verify happen synchronously
    /// here on the delegate queue (a background thread — fine to block for the multi-second hash).
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let partial = destination.appendingPathExtension("partial")
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: partial)
            try FileManager.default.moveItem(at: location, to: partial)
        } catch {
            modelLog.error("staging download failed: \(error.localizedDescription, privacy: .public)")
            Task { @MainActor in owner.apply(.failed("could not stage download: \(error.localizedDescription)")) }
            return
        }

        Task { @MainActor in owner.apply(.verifying) }
        do {
            let digest = try ModelManager.sha256(ofFileAt: partial)
            guard digest == entry.sha256 else {
                try? FileManager.default.removeItem(at: partial)
                modelLog.error("checksum mismatch expected=\(self.entry.sha256, privacy: .public) got=\(digest, privacy: .public)")
                Task { @MainActor in
                    owner.apply(.failed("checksum mismatch — download may be corrupt. Relaunch to retry."))
                }
                return
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partial, to: destination)
            modelLog.notice("model installed + verified: \(self.destination.path, privacy: .public)")
            Task { @MainActor in owner.apply(.ready) }
        } catch {
            try? FileManager.default.removeItem(at: partial)
            Task { @MainActor in owner.apply(.failed("verification failed: \(error.localizedDescription)")) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }   // success path is handled in didFinishDownloadingTo
        modelLog.error("download failed: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in
            // Don't clobber a terminal phase already set by the finish handler.
            if case .downloading = owner.phase {
                owner.apply(.failed("download failed: \(error.localizedDescription)"))
            }
        }
    }
}
