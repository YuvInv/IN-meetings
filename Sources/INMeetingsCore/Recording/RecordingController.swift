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
    private var hotKey: GlobalHotKey?
    private var tick: Timer?
    private var session: CaptureSession?
    /// Bundle id of the call app detected when this recording started (call profile) → metadata.json.
    private var recordingSourceApp: String?

    /// Runs the Python transcription pipeline for each finished recording (ADR-009).
    public let jobBridge = JobBridge()

    /// - Parameters:
    ///   - detector: source of the call-vs-no-call signal for profile auto-pick.
    ///   - installHotKey: register the global ⌃⌥⌘R toggle (false in tests, to avoid side effects).
    public init(detector: CallDetector, installHotKey: Bool = true) {
        self.detector = detector
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

        guard await Permissions.requestMicrophone() else {
            lastError = "Microphone access is required. Enable IN Meetings in System Settings ▸ Privacy & Security ▸ Microphone."
            return
        }

        let session = CaptureSession(profile: profile, directory: RecordingsStore.newMeetingDirectory())
        do {
            try session.start()
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
        tick?.invalidate()
        tick = nil
        let result = session?.stop()
        session = nil
        elapsed = 0
        state = .idle

        if let result {
            lastRecordingDir = result.directory
            let sys = result.systemPeakDB.map { String(format: "sys %.0f dB", $0) } ?? "mic-only"
            lastDiagnostic = "Last: " + String(format: "mic %.0f dB", result.micPeakDB) + " · " + sys
            captureLog.notice("recording.done profile=\(result.profile.rawValue, privacy: .public) micPeak=\(result.micPeakDB, privacy: .public)dB sysPeak=\(result.systemPeakDB ?? -120, privacy: .public)dB")

            if result.profile == .call && result.systemCapturedSilence {
                lastError = "System-audio track was silent — make sure audio is playing, and that IN Meetings has 'System Audio Recording' in System Settings (a relaunch after granting may be needed)."
            }
            // Hand the recording to the transcription pipeline (ADR-009); record-time facts feed metadata.json.
            jobBridge.enqueue(result, startedAt: startedAt, endedAt: Date(), captureSourceApp: recordingSourceApp)
            // Render the single merged playback file alongside transcription (it needs only the raw
            // tracks). Best-effort: a failure leaves no audio.m4a and the dashboard degrades.
            let dir = result.directory
            let tracks = [result.mic, result.system].compactMap { $0 }
            if !tracks.isEmpty {
                Task.detached {
                    try? await PlaybackRenderer().render(tracks: tracks,
                                                         to: dir.appendingPathComponent(PlaybackRenderer.outputName))
                }
            }
            RecordingsStore.reveal(result.directory)
        }
    }
}
