import AVFoundation
import AppKit
import Observation
import SwiftUI
import INMeetingsCore

/// Drives the first-run permission wizard: the screen sequence, the live grant actions, and the
/// `onboarding.completed` flag. UI state only — the "what's still missing / is it usable" logic lives in
/// the Core `OnboardingChecklist` (tested). Live TCC reads are cheap, so statuses are refreshed after each
/// action and on appear.
@available(macOS 14.2, *)
@MainActor
@Observable
final class OnboardingModel {
    /// One screen of the wizard (the three grants bracketed by Welcome + Done).
    enum Screen: Equatable {
        case welcome
        case grant(OnboardingStep)
        case done
    }

    let screens: [Screen] = [
        .welcome,
        .grant(.microphone),
        .grant(.screenRecording),
        .grant(.google),
        .done,
    ]

    private(set) var index = 0
    var current: Screen { screens[index] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == screens.count - 1 }

    // Live status (refreshed after actions / on appear). Google comes from the observable DriveAuth.
    private(set) var micGranted = false
    private(set) var screenGranted = false
    private(set) var screenRequested = false

    let drive: DriveAuth
    let models: ModelManager
    private let defaults: UserDefaults

    init(drive: DriveAuth, models: ModelManager, defaults: UserDefaults = .standard) {
        self.drive = drive
        self.models = models
        self.defaults = defaults
        refresh()
    }

    /// Whether the current step's grant is satisfied — so the footer can show a single primary "Continue"
    /// once done and a quiet "Skip for now" until then (no two competing primary buttons). Screen Recording
    /// counts as satisfied once requested (its grant only goes live on the restart at the end).
    var currentGrantSatisfied: Bool {
        switch current {
        case .welcome, .done: return true
        case .grant(.microphone): return micGranted
        case .grant(.screenRecording): return screenGranted || screenRequested
        case .grant(.google): return googleConnected
        }
    }

    var googleConnected: Bool {
        if case .connected = drive.status { return true }
        return false
    }

    /// A restart is only needed if the user just asked for Screen Recording but it isn't live yet (its
    /// grant takes effect on the next launch).
    var needsRestart: Bool { screenRequested && !screenGranted }

    var snapshot: PermissionsSnapshot {
        PermissionsSnapshot(micGranted: micGranted, screenGranted: screenGranted, googleConnected: googleConnected)
    }

    /// Best-effort check that the Claude Code CLI (used for auto-summary) is installed — a non-blocking
    /// info row on the Done step. Checks the usual install locations without spawning a process.
    var claudeCLIDetected: Bool {
        let candidates = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                          NSHomeDirectory() + "/.local/bin/claude"]
        return candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// One-line status of the on-device Hebrew model for the wizard — so first-run users see the ~1.5 GB
    /// download happening instead of silence.
    var modelStatus: String {
        models.isReady ? "On-device Hebrew model ready." : (models.statusText.map { $0 + " (runs in the background)" } ?? "Preparing the on-device model…")
    }

    var modelReady: Bool { models.isReady }

    func refresh() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        screenGranted = Permissions.hasScreenRecording()
    }

    // MARK: navigation

    func next() { if !isLast { index += 1 } }
    func back() { if !isFirst { index -= 1 } }
    func goTo(_ screen: Screen) { if let i = screens.firstIndex(of: screen) { index = i } }
    func restart() { index = 0; refresh() }

    // MARK: grant actions

    func requestMicrophone() async {
        _ = await Permissions.requestMicrophone()
        refresh()
    }

    func requestScreenRecording() {
        screenRequested = true
        Permissions.requestScreenRecording()
        refresh()   // stays false until relaunch — that's what drives `needsRestart`
    }

    func connectGoogle() async {
        await drive.connect()
    }

    // MARK: completion

    /// Persisted first-run flag. The wizard auto-opens at launch while this is false.
    static func hasCompleted(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Keys.completed)
    }

    func markCompleted() {
        defaults.set(true, forKey: Keys.completed)
    }

    /// Finish setup. Relaunches when a Screen-Recording grant is pending; otherwise just records completion.
    func finish() {
        markCompleted()
        if needsRestart { relaunch() }
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    private enum Keys {
        static let completed = "onboarding.completed"
    }
}
