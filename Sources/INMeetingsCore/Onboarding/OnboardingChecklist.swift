import Foundation

/// A grant the first-run wizard walks the user through.
public enum OnboardingStep: String, CaseIterable, Sendable {
    case microphone
    case systemAudio
    case screenRecording
    case google
}

/// A readable snapshot of the app's permission/connection state. System Audio Recording is deliberately
/// absent — macOS exposes no status/preflight API for it, so we can never read whether it's granted.
public struct PermissionsSnapshot: Equatable, Sendable {
    public let micGranted: Bool
    public let screenGranted: Bool
    public let googleConnected: Bool

    public init(micGranted: Bool, screenGranted: Bool, googleConnected: Bool) {
        self.micGranted = micGranted
        self.screenGranted = screenGranted
        self.googleConnected = googleConnected
    }
}

/// Pure logic shared by the onboarding wizard's recap and the dashboard's "Finish setup" nudge — one
/// source of truth for "what's still missing" and "is the app usable yet".
public enum OnboardingChecklist {
    /// Readable grants still worth nudging about. System Audio is never listed (its status can't be read);
    /// the wizard walks it live regardless.
    public static func outstanding(_ s: PermissionsSnapshot) -> [OnboardingStep] {
        var steps: [OnboardingStep] = []
        if !s.micGranted { steps.append(.microphone) }
        if !s.screenGranted { steps.append(.screenRecording) }
        if !s.googleConnected { steps.append(.google) }
        return steps
    }

    /// The "usable" floor: Microphone (record your side) + Google (backup + calendar context). Screen
    /// Recording is video-only (nice to have) and System Audio isn't readable, so neither gates this.
    public static func isSetUp(_ s: PermissionsSnapshot) -> Bool {
        s.micGranted && s.googleConnected
    }
}
