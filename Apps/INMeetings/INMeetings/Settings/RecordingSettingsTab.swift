// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingDetectionSettings (prompt toggle + global snooze + ⌃⌥⌘R hotkey); English chrome.
import SwiftUI

/// Settings → Recording: the "Record now" call-prompt master toggle, a resume control when the user has
/// snoozed prompts, and a reminder of the global record hotkey. Bound to `MeetingDetectionSettings`
/// (the same model the menu's inline toggle drives), so changes here persist via UserDefaults.
struct RecordingSettingsTab: View {
    var settings: MeetingDetectionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recording")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Prompt to record detected calls", isOn: Binding(
                    get: { settings.promptEnabled },
                    set: { settings.promptEnabled = $0 }))
                Text("Floats a “Record now” card when a call is detected. Turn off to record only manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.isSnoozed {
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .foregroundStyle(.secondary)
                    Text("Call prompts are snoozed.")
                        .foregroundStyle(.secondary)
                    Button("Resume call prompts") { settings.resume() }
                }
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                Text("Global hotkey: ⌃⌥⌘R")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
