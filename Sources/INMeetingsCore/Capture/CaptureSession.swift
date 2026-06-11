import AppKit
import Foundation

/// Orchestrates the audio tracks for one recording, per capture profile (ADR-002 / ADR-011).
///
/// - `.call`     → two tracks: `mic.wav` (you) + `system.wav` (remote participants, via the process tap)
/// - `.inPerson` → one track:  `mic.wav` (everyone on one mic; diarized downstream)
@available(macOS 14.2, *)
public final class CaptureSession {
    public struct Result: Sendable {
        public let profile: CaptureProfile
        public let directory: URL
        public let mic: URL?
        public let system: URL?
        public let micPeakDB: Float
        /// nil for in-person (no system track).
        public let systemPeakDB: Float?

        /// True if the system track only ever saw digital silence (System Audio Recording not effective,
        /// or simply nothing was playing).
        public var systemCapturedSilence: Bool { (systemPeakDB ?? -120) < -80 }
        /// True if the mic track is essentially silent.
        public var micCapturedSilence: Bool { micPeakDB < -80 }
    }

    public let profile: CaptureProfile
    public let directory: URL
    private var mic: MicRecorder?
    private var systemTap: SystemAudioTap?

    public init(profile: CaptureProfile, directory: URL) {
        self.profile = profile
        self.directory = directory
    }

    /// Creates the output folder and starts the tracks. Throws (and rolls back) on the first failure.
    public func start() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let micRec = MicRecorder(outputURL: directory.appendingPathComponent("mic.wav"))
        try micRec.start()
        mic = micRec

        if profile == .call {
            let tap = SystemAudioTap(outputURL: directory.appendingPathComponent("system.wav"))
            do {
                try tap.start()
            } catch {
                micRec.stop()
                mic = nil
                throw error
            }
            systemTap = tap
        }
    }

    /// Stops the tracks (flushing the WAVs) and reports what was captured, including peak levels.
    @discardableResult
    public func stop() -> Result {
        mic?.stop()
        systemTap?.stop()
        let result = Result(
            profile: profile,
            directory: directory,
            mic: mic?.outputURL,
            system: systemTap?.outputURL,
            micPeakDB: mic?.peakDB ?? -120,
            systemPeakDB: systemTap?.peakDB)
        mic = nil
        systemTap = nil
        return result
    }
}

/// Where recordings live locally before Drive sync (ADR-006): a per-meeting timestamped folder under
/// Application Support. Drive uses the company-first layout; this is the local cache.
public enum RecordingsStore {
    public static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("IN Meetings/Recordings", isDirectory: true)
    }

    public static func newMeetingDirectory(now: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return root.appendingPathComponent(formatter.string(from: now), isDirectory: true)
    }

    /// Reveal a folder/file in Finder (used after Stop so you can listen to the tracks).
    public static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
