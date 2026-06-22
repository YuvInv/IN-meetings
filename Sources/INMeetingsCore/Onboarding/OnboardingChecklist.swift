import Foundation

/// A grant the first-run wizard walks the user through. On macOS 15/26 system-audio capture is covered by
/// the **"Screen & System Audio Recording"** grant (the renamed Screen Recording) — there is no separate
/// system-audio permission, so it isn't its own step.
public enum OnboardingStep: String, CaseIterable, Sendable {
    case microphone
    case screenRecording
    case google
}

/// A readable snapshot of the app's permission/connection state.
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
    /// Readable grants still worth nudging about.
    public static func outstanding(_ s: PermissionsSnapshot) -> [OnboardingStep] {
        var steps: [OnboardingStep] = []
        if !s.micGranted { steps.append(.microphone) }
        if !s.screenGranted { steps.append(.screenRecording) }
        if !s.googleConnected { steps.append(.google) }
        return steps
    }

    /// The "usable" floor: Microphone (record your side) + Google (backup + calendar context). Screen &
    /// System Audio Recording is needed for the "Them" track + video but doesn't gate the usable floor.
    public static func isSetUp(_ s: PermissionsSnapshot) -> Bool {
        s.micGranted && s.googleConnected
    }
}
