// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: moved our DriveAuth connect/account/Shared-Drive-picker/disconnect flow out of the menu into a Settings Form; English chrome.
import SwiftUI
import INMeetingsCore

/// Settings → Drive: the Google account + backup-location controls that used to live in the menu's
/// `driveSection`. Disconnected → a single "Connect Google account" button; connected → the account
/// email, a picker over the user's Shared Drives (`choose` creates/persists an "IN Meetings" folder),
/// the current backup location, and a Disconnect button. Drives a `DriveAuth` (the same model `JobBridge`
/// reads), so a chosen location auto-uploads finished meetings.
struct DriveSettingsTab: View {
    var drive: DriveAuth

    @State private var pickerToken: String?
    @State private var showPicker = false
    @State private var loadingToken = false

    var body: some View {
        Form {
            Section("Google Drive") {
                switch drive.status {
                case .disconnected:
                    Button("Connect Google account") { Task { await drive.connect() } }

                case .connecting:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Connecting to Google Drive…")
                            .foregroundStyle(.secondary)
                    }

                case let .failed(message):
                    Button("Connect Google account") { Task { await drive.connect() } }
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)

                case let .connected(email):
                    connectedContent(email: email)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showPicker) {
            if let pickerToken {
                DriveFolderPickerSheet(
                    token: pickerToken,
                    onPick: { id, name in
                        showPicker = false
                        Task { await drive.chooseFolder(id: id, name: name) }
                    },
                    onClose: { showPicker = false })
            }
        }
    }

    @ViewBuilder
    private func connectedContent(email: String) -> some View {
        LabeledContent("Account") {
            Text(email)
                .foregroundStyle(.secondary)
        }

        LabeledContent("Backup location") {
            Text(drive.location?.displayName ?? "Not set")
                .foregroundStyle(.secondary)
        }

        // The real Google Drive web-view picker: browse My Drive + Shared Drives, pick any folder.
        Button {
            Task {
                loadingToken = true
                pickerToken = await drive.pickerAccessToken()
                loadingToken = false
                if pickerToken != nil { showPicker = true }
            }
        } label: {
            Label(drive.location == nil ? "Choose folder in Google Drive…" : "Change backup folder…",
                  systemImage: "folder.badge.gearshape")
        }
        .disabled(loadingToken)

        HStack {
            if loadingToken {
                ProgressView().controlSize(.small)
                Text("Opening Drive…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Disconnect", role: .destructive) { drive.disconnect() }
        }
    }
}
