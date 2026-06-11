import SwiftUI
import AppKit
import INMeetingsCore

/// IN-meetings menu-bar app entry point.
///
/// Slice 1 is intentionally a bare shell: a `MenuBarExtra` (waveform icon) that proves the app
/// builds, is signed, and launches as a menu-bar agent (`LSUIElement`, no Dock icon). Detection
/// (Slice 2) and capture (Slice 3) get wired into the menu and the disabled action below.
@main
struct INMeetingsApp: App {
    var body: some Scene {
        MenuBarExtra("IN Meetings", systemImage: "waveform") {
            MenuContent()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuContent: View {
    var body: some View {
        Text("IN Meetings — idle")

        Divider()

        Button("Start Recording") {
            // Wired in Slice 2 (manual start + profile auto-pick).
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
