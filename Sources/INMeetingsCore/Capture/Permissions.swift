import AVFoundation
import AppKit

/// TCC helpers for the capture grants the MVP needs: Microphone and System Audio Recording.
///
/// Microphone has an explicit async request API. System Audio Recording does not — the prompt fires
/// when the process tap is first created (`SystemAudioTap`); denial shows up as a silent system track,
/// which `CaptureSession.Result.systemCapturedSilence` flags.
public enum Permissions {
    /// Returns true if the mic is (or becomes) authorized. Prompts once when undetermined.
    public static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Open System Settings ▸ Privacy & Security (Microphone pane; System Audio Recording sits alongside).
    public static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
