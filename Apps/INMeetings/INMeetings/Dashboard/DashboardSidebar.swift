// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.

import SwiftUI

struct DashboardSidebar: View {
    @Binding var selection: DashboardSelection?
    var body: some View {
        List(selection: $selection) {
            Label("All Meetings", systemImage: "tray.full").tag(DashboardSelection.allMeetings)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                SettingsLink { Label("Settings", systemImage: "gear").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(10)
            }
        }
    }
}
