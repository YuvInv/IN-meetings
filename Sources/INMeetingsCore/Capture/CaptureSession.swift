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
        /// The call-window video (`video.mov`), when video capture was on and produced frames; else nil.
        public let video: URL?

        public init(profile: CaptureProfile, directory: URL, mic: URL?, system: URL?,
                    micPeakDB: Float, systemPeakDB: Float?, video: URL? = nil) {
            self.profile = profile
            self.directory = directory
            self.mic = mic
            self.system = system
            self.micPeakDB = micPeakDB
            self.systemPeakDB = systemPeakDB
            self.video = video
        }

        /// True if the system track only ever saw digital silence (System Audio Recording not effective,
        /// or simply nothing was playing).
        public var systemCapturedSilence: Bool { (systemPeakDB ?? -120) < -80 }
        /// True if the mic track is essentially silent.
        public var micCapturedSilence: Bool { micPeakDB < -80 }
    }

    public let profile: CaptureProfile
    public let directory: URL
    /// The call app's bundle id (e.g. "com.google.Chrome") to scope window-only video capture — nil to
    /// record audio only (in-person, video disabled, or no detected app). Only used for the `call` profile.
    private let videoBundleID: String?
    private var mic: MicRecorder?
    private var systemTap: SystemAudioTap?
    private var videoRecorder: ScreenCaptureKitRecorder?

    public init(profile: CaptureProfile, directory: URL, videoBundleID: String? = nil) {
        self.profile = profile
        self.directory = directory
        self.videoBundleID = videoBundleID
    }

    /// Creates the output folder and starts the tracks. Audio (mic + system tap) is critical and rolls
    /// back on failure; the call-window video is best-effort — a Screen-Recording denial or a missing
    /// window logs and degrades to audio-only rather than failing the recording.
    public func start() async throws {
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

            if let videoBundleID {
                let recorder = ScreenCaptureKitRecorder(
                    outputURL: directory.appendingPathComponent("video.mov"), bundleID: videoBundleID)
                do {
                    try await recorder.start()
                    videoRecorder = recorder
                } catch {
                    captureLog.error("video.start skipped: \((error as? CaptureError)?.description ?? error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Stops the tracks (flushing the WAVs, finalizing the video) and reports what was captured.
    @discardableResult
    public func stop() async -> Result {
        mic?.stop()
        systemTap?.stop()
        let videoURL = await videoRecorder?.stop()
        let result = Result(
            profile: profile,
            directory: directory,
            mic: mic?.outputURL,
            system: systemTap?.outputURL,
            micPeakDB: mic?.peakDB ?? -120,
            systemPeakDB: systemTap?.peakDB,
            video: videoURL)
        mic = nil
        systemTap = nil
        videoRecorder = nil
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
