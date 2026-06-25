import SwiftUI
import INMeetingsCore

/// Settings → Calendar: connect (or reconnect) the Google account that powers the dashboard's day-agenda
/// panel. Calendar and Drive share **one** Google sign-in — the same OAuth scopes
/// (`…/auth/calendar.events.readonly` + `…/auth/drive`) and the same Keychain credential — so this drives
/// the same `DriveAuth` the Drive tab does: connecting here also enables Drive backup, and **Reconnect**
/// re-runs the sign-in to refresh the stored token (the fix when the agenda stops loading after a token
/// expires). Disconnecting + the backup folder live in the Drive tab so there's one place to sever the
/// shared account.
struct CalendarSettingsTab: View {
    var drive: DriveAuth

    var body: some View {
        Form {
            Section("Google Calendar") {
                switch drive.status {
                case .disconnected:
                    Text("Connect your Google account to see your calendar in the dashboard and import recordings against scheduled events.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Connect Google Calendar…") { Task { await drive.connect() } }

                case .connecting:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Connecting to Google…")
                            .foregroundStyle(.secondary)
                    }

                case let .failed(message):
                    Button("Connect Google Calendar…") { Task { await drive.connect() } }
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)

                case let .connected(email):
                    LabeledContent("Account") {
                        Text(email).foregroundStyle(.secondary)
                    }
                    Label("Calendar connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    // Re-runs the Google sign-in and refreshes the stored token. Use this if the dashboard
                    // agenda stops loading (e.g. the saved token expired and couldn't refresh).
                    Button("Reconnect…") { Task { await drive.connect() } }
                }
            }

            Section {
                Text("One Google sign-in covers both Calendar and Drive. Manage your backup folder and disconnect in the Drive tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
