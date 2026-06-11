import SwiftUI
import AppKit
import INMeetingsCore

/// IN-meetings menu-bar app entry point.
///
/// Slice 2 wires live call detection (P3) plus the manual Start/Stop flow: a `CallDetector` polls
/// Core Audio process I/O, and a `RecordingController` (toggled by the menu or the global ⌃⌥⌘R hotkey)
/// auto-picks the capture profile. While recording, the menu-bar label shows a live running timer.
/// Real audio capture (slice 3) plugs into the controller.
@main
struct INMeetingsApp: App {
    @State private var detector: CallDetector
    @State private var recorder: RecordingController

    init() {
        let detector = CallDetector()
        _detector = State(initialValue: detector)
        _recorder = State(initialValue: RecordingController(detector: detector))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(detector: detector, recorder: recorder)
        } label: {
            // Recording → live "🔴 m:ss" timer (the status item re-renders on each `elapsed` tick).
            // Idle → waveform, filled when a call is detected.
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

            Button("Start Recording") { recorder.start() }
            Text("→ will record: \(recorder.pendingProfile.label)")

        case let .recording(profile, _):
            Text("🔴 Recording — \(profile.label)")
            Text("Elapsed \(recorder.elapsedString)")

            Divider()

            Button("Stop Recording") { recorder.stop() }
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
