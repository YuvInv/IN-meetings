// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt for INV Meetings General settings (launch-at-login + version).
import SwiftUI
import INMeetingsCore

/// Settings → General: launch-at-login toggle and the running app version.
struct GeneralSettingsTab: View {
    var launchAtLogin: LaunchAtLoginManaging

    @State private var isEnabled: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch INV Meetings at login", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        do {
                            try launchAtLogin.setEnabled(newValue)
                            errorMessage = nil
                        } catch {
                            errorMessage = "Could not update login item: \(error.localizedDescription)"
                            // Roll back the toggle state to reflect actual system state
                            isEnabled = launchAtLogin.isEnabled
                        }
                    }
                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Start INV Meetings automatically when you log in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text(versionString())
                .foregroundStyle(.secondary)
                .font(.caption)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { isEnabled = launchAtLogin.isEnabled }
    }
}
