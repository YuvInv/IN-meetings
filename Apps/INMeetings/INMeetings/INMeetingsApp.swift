import SwiftUI
import AppKit
import INMeetingsCore

/// IN-meetings menu-bar app entry point.
///
/// Wires live call detection (P3) + the manual Start/Stop flow + dual-track capture (P2): a
/// `CallDetector` polls Core Audio process I/O, and a `RecordingController` (toggled by the menu or
/// the global ⌃⌥⌘R hotkey) auto-picks the profile and records. While recording, the menu-bar label
/// shows a live running timer. On first launch a `ModelManager` downloads + verifies the Hebrew ASR
/// model, gating Start until the pipeline has a model to run. A `MeetingPromptCoordinator` floats a
/// Liquid Glass "Record now" card whenever a call is detected (Harvest 3). `DriveAuth` connects a
/// Google account + backup location so finished meetings sync to Drive (slice 6).
@main
struct INMeetingsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var detector: CallDetector
    @State private var recorder: RecordingController
    @State private var models: ModelManager
    @State private var vadModel: ModelManager
    @State private var promptSettings: MeetingDetectionSettings
    @State private var captureSettings: CaptureSettings
    @State private var audioDeviceSettings: AudioDeviceSettings
    @State private var promptCoordinator: MeetingPromptCoordinator
    @State private var endCoordinator: MeetingEndCoordinator
    @State private var drive: DriveAuth
    @State private var onboarding: OnboardingModel

    init() {
        let detector = CallDetector()
        _detector = State(initialValue: detector)
        let captureSettings = CaptureSettings()
        _captureSettings = State(initialValue: captureSettings)
        let audioDeviceSettings = AudioDeviceSettings()
        _audioDeviceSettings = State(initialValue: audioDeviceSettings)
        let recorder = RecordingController(detector: detector, captureSettings: captureSettings,
                                           audioDeviceSettings: audioDeviceSettings)
        _recorder = State(initialValue: recorder)
        let models = ModelManager()
        _models = State(initialValue: models)
        models.ensureReady()   // download + verify the Hebrew model on first launch (Harvest 1)
        let vadModel = ModelManager(entry: ModelCatalog.sileroVad)
        _vadModel = State(initialValue: vadModel)
        vadModel.ensureReady()   // tiny Silero VAD so the pipeline runs --vad (no silence hallucination)
        let settings = MeetingDetectionSettings()
        _promptSettings = State(initialValue: settings)
        let coordinator = MeetingPromptCoordinator(detector: detector, recorder: recorder, settings: settings)
        _promptCoordinator = State(initialValue: coordinator)
        coordinator.start()   // float a "Record now" card on each detected call (Harvest 3)
        let endCoordinator = MeetingEndCoordinator(detector: detector, recorder: recorder, settings: settings)
        _endCoordinator = State(initialValue: endCoordinator)
        endCoordinator.start()   // float a "Meeting ended — stopping in Ns…" countdown when a recorded call ends
        let drive = DriveAuth()
        _drive = State(initialValue: drive)
        _onboarding = State(initialValue: OnboardingModel(drive: drive, models: models))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(detector: detector, recorder: recorder, models: models,
                        settings: promptSettings, coordinator: promptCoordinator,
                        endCoordinator: endCoordinator, drive: drive, onboarding: onboarding)
        } label: {
            MenuBarLabel(detector: detector, recorder: recorder)
        }
        .menuBarExtraStyle(.menu)

        Window("INV Meetings", id: "dashboard") {
            DashboardWindow(drive: drive, jobBridge: recorder.jobBridge)
        }
        .windowResizability(.contentSize)

        Window("Set up INV Meetings", id: "onboarding") {
            OnboardingWindow(model: onboarding)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            AppSettingsView(settings: promptSettings, models: models, vadModels: vadModel,
                            drive: drive, capture: captureSettings, audio: audioDeviceSettings)
        }
    }
}

private struct MenuContent: View {
    var detector: CallDetector
    var recorder: RecordingController
    var models: ModelManager
    var settings: MeetingDetectionSettings
    var coordinator: MeetingPromptCoordinator
    var endCoordinator: MeetingEndCoordinator
    var drive: DriveAuth
    var onboarding: OnboardingModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Dashboard") {
            NSApp.activate(ignoringOtherApps: true)   // hybrid Dock + menu-bar app: bring the dashboard forward
            openWindow(id: "dashboard")
        }
        .keyboardShortcut("d")
        Button("Set up INV Meetings…") {
            onboarding.restart()
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "onboarding")
        }
        Divider()

        switch recorder.state {
        case .idle:
            switch detector.state.status {
            case .armed:
                Text("● Call detected — \(detector.state.callApps.joined(separator: ", "))")
            case .idle:
                Text("○ No call detected")
            }

            Divider()

            if models.isReady {
                Button("Start Recording") { Task { await recorder.start() } }
                Text("→ will record: \(recorder.pendingProfile.label)")
            } else {
                Text(models.statusText ?? "Preparing model…")
                if case .failed = models.phase {
                    Button("Retry Model Download") { models.retry() }
                }
                Button("Start Recording") { Task { await recorder.start() } }
                    .disabled(true)
            }

        case let .recording(profile, _):
            Text("🔴 Recording — \(profile.label)")
            Text("Elapsed \(recorder.elapsedString)")

            Divider()

            Button("Stop Recording") { recorder.stop() }
        }

        if let diagnostic = recorder.lastDiagnostic, !recorder.isRecording {
            Text(diagnostic)
        }

        if let phase = recorder.jobBridge.phase, !recorder.isRecording {
            Text("Pipeline: \(phase)")
        }

        if let error = recorder.lastError {
            Divider()
            Text("⚠️ \(error)")
            Button("Open Privacy Settings…") { Permissions.openPrivacySettings() }
        }

        if let dir = recorder.lastRecordingDir, !recorder.isRecording {
            Button("Reveal Last Recording") { RecordingsStore.reveal(dir) }
        }

        Divider()

        Text("⌃⌥⌘R toggles recording")

        Toggle("Prompt to record detected calls", isOn: Binding(
            get: { settings.promptEnabled },
            set: { settings.promptEnabled = $0 }))
        if settings.isSnoozed {
            Button("Resume call prompts") { settings.resume() }
        }
        Toggle("Offer to stop when the call ends", isOn: Binding(
            get: { settings.autoStopEnabled },
            set: { settings.autoStopEnabled = $0 }))

        #if DEBUG
        Button("Preview record prompt (debug)") { coordinator.previewPrompt() }
        Button("Preview meeting-ended countdown (debug)") { endCoordinator.previewCountdown() }
        #endif

        Divider()

        driveSection

        Divider()

        Text("core v\(INMeetingsCore.version)")

        Button("Quit INV Meetings") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Connect a Google account + choose a backup Shared Drive (slice 6). Once both are set, finished
    /// meetings upload automatically (handled in Core by `JobBridge`'s `DriveBackup`).
    @ViewBuilder
    private var driveSection: some View {
        switch drive.status {
        case .disconnected:
            Button("Connect Google Drive…") { Task { await drive.connect() } }
        case .connecting:
            Text("Connecting to Google Drive…")
        case let .failed(message):
            Button("Connect Google Drive…") { Task { await drive.connect() } }
            Text("⚠️ Drive: \(message)")
        case let .connected(email):
            Text("Drive: \(email)")
            Menu(drive.location.map { "Backup: \($0.displayName)" } ?? "Choose backup location…") {
                if drive.sharedDrives.isEmpty {
                    Text("No Shared Drives found")
                } else {
                    ForEach(drive.sharedDrives, id: \.id) { sharedDrive in
                        Button(sharedDrive.name) { Task { await drive.choose(sharedDrive) } }
                    }
                }
                Divider()
                Button("Refresh drives") { Task { await drive.refreshSharedDrives() } }
            }
            Button("Disconnect Drive") { drive.disconnect() }
        }
    }
}

/// Bridges AppKit lifecycle callbacks (Dock-icon clicks, last-window-closed) to SwiftUI's `openWindow`
/// action, which `NSApplicationDelegate` cannot reach (it has no SwiftUI environment). The closure is
/// installed by `MenuBarLabel` — the one SwiftUI view that is always present (the menu-bar status item).
@MainActor
final class DashboardLauncher {
    static let shared = DashboardLauncher()
    /// Set once by `MenuBarLabel.onAppear`; calls `openWindow(id: "dashboard")`.
    var open: (() -> Void)?
    /// Set alongside `open`; calls `openWindow(id: "onboarding")` for the first-run wizard.
    var openOnboarding: (() -> Void)?
    private init() {}
}

/// Hybrid Dock + menu-bar lifecycle. The app is a regular, Dock-visible app (`LSUIElement=false`) that
/// also lives in the menu bar: closing the dashboard must NOT quit the recorder, and clicking the Dock
/// icon (re)opens the dashboard. Amends ADR-001/ADR-009 (was a pure `LSUIElement` menu-bar agent).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keep the recorder + menu-bar item alive when the dashboard window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Dock-icon click with no visible window → bring the app forward and (re)open the dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.activate(ignoringOtherApps: true)
            DashboardLauncher.shared.open?()
        }
        return true
    }

    /// Open the dashboard on launch so it feels like a real app. (P0 #2 / launch-at-login will gate this
    /// so a *login-item* start stays quiet in the background instead of popping the window.) On first run,
    /// also float the onboarding wizard in front (the dashboard stays usable behind it).
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            DashboardLauncher.shared.open?()
            if !OnboardingModel.hasCompleted() {
                NSApp.activate(ignoringOtherApps: true)
                DashboardLauncher.shared.openOnboarding?()
            }
        }
    }
}

/// The menu-bar status item: draws the icon/timer AND installs the `DashboardLauncher` closure. It is the
/// only always-present SwiftUI view in this app, so its environment is where we capture `openWindow`.
private struct MenuBarLabel: View {
    var detector: CallDetector
    var recorder: RecordingController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if recorder.isRecording {
                Text("🔴 \(recorder.elapsedString)")
                    .monospacedDigit()
            } else {
                Image("MenuBarIcon")
                    .renderingMode(.original)
            }
        }
        .onAppear {
            DashboardLauncher.shared.open = { openWindow(id: "dashboard") }
            DashboardLauncher.shared.openOnboarding = { openWindow(id: "onboarding") }
        }
    }
}
