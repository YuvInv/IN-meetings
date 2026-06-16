import Foundation
import Observation

/// Drives the manual Start/Stop flow, picks the capture profile (ADR-011), and owns the capture session.
///
/// Start requests the Microphone grant, then spins up a `CaptureSession` for the auto-picked profile
/// (call → dual-track, in-person → mic only). A global hotkey (⌃⌥⌘R) toggles it. `elapsed` ticks once a
/// second to drive the live menu-bar timer. After each recording, `lastDiagnostic` reports peak levels
/// (a self-check that audio was actually captured); capture/permission problems surface via `lastError`.
@available(macOS 14.2, *)
@MainActor
@Observable
public final class RecordingController {
    public enum State: Equatable {
        case idle
        case recording(profile: CaptureProfile, since: Date)
    }

    public private(set) var state: State = .idle
    /// Seconds since recording started; 0 when idle. Drives the live menu-bar timer.
    public private(set) var elapsed: TimeInterval = 0
    /// Peak-level self-check from the last recording (e.g. "Last: mic −15 dB · sys −42 dB").
    public private(set) var lastDiagnostic: String?
    /// Most recent capture/permission problem to surface in the menu (nil if none).
    public private(set) var lastError: String?
    /// Folder of the most recently finished recording (for "Reveal in Finder").
    public private(set) var lastRecordingDir: URL?

    private let detector: CallDetector
    private let captureSettings: CaptureSettings
    private var hotKey: GlobalHotKey?
    private var tick: Timer?
    private var session: CaptureSession?
    /// Friendly name of the call app detected when this recording started (call profile) → metadata.json.
    private var recordingSourceApp: String?
    /// Bundle id of the call app to film window-only video (nil = audio only) — captured at Start.
    private var recordingVideoBundleID: String?

    /// Runs the Python transcription pipeline for each finished recording (ADR-009).
    public let jobBridge = JobBridge()

    /// - Parameters:
    ///   - detector: source of the call-vs-no-call signal for profile auto-pick.
    ///   - captureSettings: video on/off + retention prefs (V1 video slice).
    ///   - installHotKey: register the global ⌃⌥⌘R toggle (false in tests, to avoid side effects).
    public init(detector: CallDetector, captureSettings: CaptureSettings? = nil,
                installHotKey: Bool = true) {
        self.detector = detector
        self.captureSettings = captureSettings ?? CaptureSettings()
        if installHotKey {
            hotKey = GlobalHotKey { [weak self] in self?.toggle() }
        }
    }

    public var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    /// The profile Start would pick right now, given the current detection state.
    public var pendingProfile: CaptureProfile {
        CaptureProfile.autoPick(callDetected: detector.state.status == .armed)
    }

    /// `m:ss`, or `h:mm:ss` past an hour.
    public var elapsedString: String {
        let t = Int(elapsed)
        let (h, m, s) = (t / 3600, (t % 3600) / 60, t % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    public func toggle() {
        if isRecording { stop() } else { Task { await start() } }
    }

    public func start() async {
        guard !isRecording else { return }
        lastError = nil
        let profile = pendingProfile
        recordingSourceApp = profile == .call ? detector.state.callApps.first : nil
        // Film the call window only for a call, only when the user left video on, and only if we know
        // which app hosts the call (the SCK content filter needs a bundle id).
        recordingVideoBundleID = (profile == .call && captureSettings.recordCallVideo)
            ? detector.state.callAppBundleIDs.first : nil

        guard await Permissions.requestMicrophone() else {
            lastError = "Microphone access is required. Enable IN Meetings in System Settings ▸ Privacy & Security ▸ Microphone."
            return
        }
        // Provoke the Screen-Recording prompt up front (best-effort) so the user can grant it; the grant
        // takes effect on a later run, and capture degrades to audio-only until then.
        if recordingVideoBundleID != nil { Permissions.requestScreenRecording() }

        let session = CaptureSession(profile: profile, directory: RecordingsStore.newMeetingDirectory(),
                                     videoBundleID: recordingVideoBundleID)
        do {
            try await session.start()
        } catch {
            lastError = (error as? CaptureError)?.description ?? error.localizedDescription
            return
        }

        self.session = session
        state = .recording(profile: profile, since: Date())
        elapsed = 0
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, case let .recording(_, since) = self.state else { return }
                self.elapsed = Date().timeIntervalSince(since)
            }
        }
    }

    public func stop() {
        guard isRecording else { return }
        let startedAt: Date = {
            if case let .recording(_, since) = state { return since }
            return Date()
        }()
        let endedAt = Date()
        tick?.invalidate()
        tick = nil
        let session = self.session
        self.session = nil
        // Snapshot the record-time facts now — finalizing the video is async, and a rapid stop→start
        // must not let the next recording's source app leak into this one's metadata.
        let sourceApp = recordingSourceApp
        elapsed = 0
        state = .idle
        guard let session else { return }
        // Stopping is async now (the video writer is finalized) — do it off the synchronous toggle, then
        // hand the result to the pipeline + renderer on the main actor.
        Task { @MainActor in
            let result = await session.stop()
            self.finish(result, startedAt: startedAt, endedAt: endedAt, captureSourceApp: sourceApp)
        }
    }

    private func finish(_ result: CaptureSession.Result, startedAt: Date, endedAt: Date,
                        captureSourceApp: String?) {
        lastRecordingDir = result.directory
        let sys = result.systemPeakDB.map { String(format: "sys %.0f dB", $0) } ?? "mic-only"
        lastDiagnostic = "Last: " + String(format: "mic %.0f dB", result.micPeakDB) + " · " + sys
        captureLog.notice("recording.done profile=\(result.profile.rawValue, privacy: .public) micPeak=\(result.micPeakDB, privacy: .public)dB sysPeak=\(result.systemPeakDB ?? -120, privacy: .public)dB video=\(result.video != nil, privacy: .public)")

        if result.profile == .call && result.systemCapturedSilence {
            lastError = "System-audio track was silent — make sure audio is playing, and that IN Meetings has 'System Audio Recording' in System Settings (a relaunch after granting may be needed)."
        }
        // Hand the recording to the transcription pipeline (ADR-009); record-time facts feed metadata.json.
        jobBridge.enqueue(result, startedAt: startedAt, endedAt: endedAt, captureSourceApp: captureSourceApp)
        // Render the single merged playback file alongside transcription (it needs only the raw tracks).
        // With a call video → `meeting.mp4` (window video + level-balanced audio); audio-only → `audio.m4a`.
        // Best-effort: a failure leaves the dashboard/Drive to fall back to the raw tracks.
        let dir = result.directory
        // Pair each track with its A/V offset so the mux can align them (unified video capture); the
        // audio-only path leaves offsets nil → 0.
        let trackOffsets: [(URL, Double)] = [
            result.mic.map { ($0, result.micOffset ?? 0) },
            result.system.map { ($0, result.systemOffset ?? 0) },
        ].compactMap { $0 }
        let video = result.video
        if !trackOffsets.isEmpty {
            let tracks = trackOffsets.map(\.0)
            let offsets = trackOffsets.map(\.1)
            Task.detached {
                let out = dir.appendingPathComponent(
                    video != nil ? PlaybackRenderer.videoOutputName : PlaybackRenderer.outputName)
                try? await PlaybackRenderer().render(tracks: tracks, offsets: offsets, video: video, to: out)
                // meeting.mp4 now carries the picture (passthrough-copied) — drop the raw video.mov to
                // reclaim disk immediately, once the mux actually produced the file.
                if let video, FileManager.default.fileExists(atPath: out.path) {
                    try? FileManager.default.removeItem(at: video)
                }
            }
        }
        RecordingsStore.reveal(result.directory)
    }
}
