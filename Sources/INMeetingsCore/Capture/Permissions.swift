import AVFoundation
import AppKit
import CoreGraphics

/// TCC helpers for the capture grants the app needs: Microphone, System Audio Recording, and — once
/// call video lands (V1) — Screen Recording.
///
/// Microphone has an explicit async request API. System Audio Recording does not — the prompt fires
/// when the process tap is first created (`SystemAudioTap`); denial shows up as a silent system track,
/// which `CaptureSession.Result.systemCapturedSilence` flags. Screen Recording uses the CoreGraphics
/// preflight/request SPIs; the grant only takes effect on a later launch.
public enum Permissions {
    /// Returns true if the mic is (or becomes) authorized. Prompts once when undetermined.
    public static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Whether Screen Recording is already granted (no prompt).
    public static func hasScreenRecording() -> Bool { CGPreflightScreenCaptureAccess() }

    /// Ask for Screen Recording (needed to film the call window). Returns true if already granted; when
    /// not, macOS shows the prompt + adds the app to the Screen Recording list, and the grant takes
    /// effect on the next launch (so capture degrades to audio-only until then).
    @discardableResult
    public static func requestScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }

    /// Open System Settings ▸ Privacy & Security (Microphone pane; System Audio Recording sits alongside).
    public static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings ▸ Privacy & Security ▸ Screen Recording (for the onboarding/settings nudge).
    public static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
