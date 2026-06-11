import Foundation
import Observation

/// Drives the manual Start/Stop flow and picks the capture profile (ADR-011).
///
/// Slice 2b is the control-flow state machine only: Start auto-picks the profile from the detector
/// and transitions to `.recording`; Stop returns to `.idle`. A global hotkey (⌃⌥⌘R) toggles it. Real
/// audio capture (a `CaptureSession`) plugs into `start()`/`stop()` in slice 3.
///
/// `elapsed` is updated once a second so the menu-bar label can show a live running timer (a native
/// `NSMenu` dropdown can't tick a SwiftUI timer, but the status-item label re-renders on this change).
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

    private let detector: CallDetector
    private var hotKey: GlobalHotKey?
    private var tick: Timer?

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

    public func start() {
        guard !isRecording else { return }
        let now = Date()
        state = .recording(profile: pendingProfile, since: now)
        elapsed = 0
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, case let .recording(_, since) = self.state else { return }
                self.elapsed = Date().timeIntervalSince(since)
            }
        }
        // Slice 3: spin up the CaptureSession for `profile` here.
    }

    public func stop() {
        guard isRecording else { return }
        tick?.invalidate()
        tick = nil
        elapsed = 0
        state = .idle
        // Slice 3: finalize capture and hand the recording to the pipeline.
    }

    public func toggle() {
        isRecording ? stop() : start()
    }
}
