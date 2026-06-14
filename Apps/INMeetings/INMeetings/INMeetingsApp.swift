import SwiftUI
import AppKit
import INMeetingsCore

/// IN-meetings menu-bar app entry point.
///
/// Wires live call detection (P3) + the manual Start/Stop flow + dual-track capture (P2): a
/// `CallDetector` polls Core Audio process I/O, and a `RecordingController` (toggled by the menu or
/// the global ⌃⌥⌘R hotkey) auto-picks the profile and records. While recording, the menu-bar label
/// shows a live running timer. On first launch a `ModelManager` downloads + verifies the Hebrew ASR
/// model, gating Start until the pipeline has a model to run.
@main
struct INMeetingsApp: App {
    @State private var detector: CallDetector
    @State private var recorder: RecordingController
    @State private var models: ModelManager

    init() {
        let detector = CallDetector()
        _detector = State(initialValue: detector)
        _recorder = State(initialValue: RecordingController(detector: detector))
        let models = ModelManager()
        _models = State(initialValue: models)
        models.ensureReady()   // download + verify the Hebrew model on first launch (Harvest 1)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(detector: detector, recorder: recorder, models: models)
        } label: {
            if recorder.isRecording {
                Text("🔴 \(recorder.elapsedString)")
                    .monospacedDigit()
            } else {
                Image(systemName: detector.state.status == .armed ? "waveform.circle.fill" : "waveform")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuContent: View {
    var detector: CallDetector
    var recorder: RecordingController
    var models: ModelManager

    var body: some View {
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

        Divider()

        Text("core v\(INMeetingsCore.version)")

        Button("Quit IN Meetings") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
