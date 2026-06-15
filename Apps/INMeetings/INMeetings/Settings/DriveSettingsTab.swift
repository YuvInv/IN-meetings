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
    }

    @ViewBuilder
    private func connectedContent(email: String) -> some View {
        LabeledContent("Account") {
            Text(email)
                .foregroundStyle(.secondary)
        }

        if drive.sharedDrives.isEmpty {
            LabeledContent("Backup drive") {
                Text("No Shared Drives found")
                    .foregroundStyle(.secondary)
            }
        } else {
            Picker("Backup drive", selection: driveSelection) {
                Text("Choose a Shared Drive…").tag(String?.none)
                ForEach(drive.sharedDrives, id: \.id) { sharedDrive in
                    Text(sharedDrive.name).tag(Optional(sharedDrive.id))
                }
            }
        }

        LabeledContent("Backup location") {
            Text(drive.location?.displayName ?? "Not set")
                .foregroundStyle(.secondary)
        }

        HStack {
            Button("Refresh drives") { Task { await drive.refreshSharedDrives() } }
            Spacer()
            Button("Disconnect", role: .destructive) { drive.disconnect() }
        }
    }

    /// The Shared Drive currently backing the persisted location. Selecting a different one runs
    /// `choose`, which finds/creates the "IN Meetings" folder on that drive and persists it.
    private var driveSelection: Binding<String?> {
        Binding(
            get: { drive.location?.driveID },
            set: { newID in
                guard let newID,
                      newID != drive.location?.driveID,
                      let picked = drive.sharedDrives.first(where: { $0.id == newID })
                else { return }
                Task { await drive.choose(picked) }
            })
    }
}
