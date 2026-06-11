import SwiftUI
import AppKit
import INMeetingsCore

/// IN-meetings menu-bar app entry point.
///
/// Slice 2 wires live call detection (prototype P3): a `CallDetector` polls Core Audio process I/O
/// and the menu + icon reflect whether a call is in progress. Manual Start + global hotkey (slice 2b)
/// and dual-track capture (slice 3) build on this. No TCC is needed for detection.
@main
struct INMeetingsApp: App {
    @State private var detector = CallDetector()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(detector: detector)
        } label: {
            Image(systemName: detector.state.status == .armed ? "waveform.circle.fill" : "waveform")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuContent: View {
    var detector: CallDetector

    var body: some View {
        switch detector.state.status {
        case .armed:
            Text("● Call detected — \(detector.state.callApps.joined(separator: ", "))")
        case .idle:
            Text("○ No call detected")
        }

        Divider()

        Button("Start Recording") {
            // Wired in slice 2b (manual start + profile auto-pick).
        }
        .disabled(true)

        Divider()

        Text("core v\(INMeetingsCore.version)")

        Button("Quit IN Meetings") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
