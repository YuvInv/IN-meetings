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
        /// A/V start offsets (seconds) of each audio track relative to the first video frame, on the
        /// unified-capture clock — so the playback mux aligns at the real offset, not t=0. nil with no video.
        public let micOffset: Double?
        public let systemOffset: Double?

        public init(profile: CaptureProfile, directory: URL, mic: URL?, system: URL?,
                    micPeakDB: Float, systemPeakDB: Float?, video: URL? = nil,
                    micOffset: Double? = nil, systemOffset: Double? = nil) {
            self.profile = profile
            self.directory = directory
            self.mic = mic
            self.system = system
            self.micPeakDB = micPeakDB
            self.systemPeakDB = systemPeakDB
            self.video = video
            self.micOffset = micOffset
            self.systemOffset = systemOffset
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
    /// Persistent UID of the input device to record the mic from, or nil for the system default. Already
    /// resolved against the available devices by the caller (an unplugged device degrades to nil).
    private let micDeviceUID: String?
    /// Opt-in auto-leveling for the mic track; nil leaves the raw mic untouched.
    private let adaptiveGain: AdaptiveGain?
    private var mic: MicRecorder?
    private var systemTap: SystemAudioTap?
    private var callRecorder: ScreenCaptureKitRecorder?

    public init(profile: CaptureProfile, directory: URL, videoBundleID: String? = nil,
                micDeviceUID: String? = nil, adaptiveGain: AdaptiveGain? = nil) {
        self.profile = profile
        self.directory = directory
        self.videoBundleID = videoBundleID
        self.micDeviceUID = micDeviceUID
        self.adaptiveGain = adaptiveGain
    }

    /// Creates the output folder and starts capture. A **video call** runs one ScreenCaptureKit stream
    /// (screen + system + mic on one clock) so the merged file is A/V-synced by construction (amends
    /// ADR-002); if that can't start it falls back to the audio path. **In-person / call-without-video**
    /// use the audio path: mic via AVAudioEngine (+ system via the Core Audio tap for calls), no Screen
    /// Recording. Audio is critical (rolls back on failure); video is best-effort.
    ///
    /// `micDeviceUID` selects the input device on both paths (best-effort on the SCK path); `adaptiveGain`
    /// applies **only** on the audio path (`MicRecorder`) — a video call records the raw chosen mic.
    public func start() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if profile == .call, let videoBundleID {
            let recorder = ScreenCaptureKitRecorder(directory: directory, bundleID: videoBundleID,
                                                    micDeviceUID: micDeviceUID)
            do {
                try await recorder.start()
                callRecorder = recorder
                return   // unified path writes mic.wav + system.wav + video.mov itself
            } catch {
                captureLog.error("unified capture failed, falling back to audio-only: \((error as? CaptureError)?.description ?? error.localizedDescription, privacy: .public)")
            }
        }

        let micRec = MicRecorder(outputURL: directory.appendingPathComponent("mic.wav"),
                                 deviceUID: micDeviceUID, adaptiveGain: adaptiveGain)
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

    /// Stops capture (flushing the WAVs, finalizing the video) and reports what was captured + the A/V
    /// offsets (unified path only).
    @discardableResult
    public func stop() async -> Result {
        if let callRecorder {
            let out = await callRecorder.stop()
            self.callRecorder = nil
            return Result(profile: profile, directory: directory,
                          mic: out.mic, system: out.system,
                          micPeakDB: out.micPeakDB, systemPeakDB: out.systemPeakDB,
                          video: out.video, micOffset: out.micOffset, systemOffset: out.systemOffset)
        }
        mic?.stop()
        systemTap?.stop()
        let result = Result(
            profile: profile,
            directory: directory,
            mic: mic?.outputURL,
            system: systemTap?.outputURL,
            micPeakDB: mic?.peakDB ?? -120,
            systemPeakDB: systemTap?.peakDB,
            video: nil)
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
