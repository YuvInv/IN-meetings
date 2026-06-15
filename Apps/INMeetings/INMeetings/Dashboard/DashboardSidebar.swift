// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.

import SwiftUI

struct DashboardSidebar: View {
    @Binding var selection: DashboardSelection?
    let needsLinkingCount: Int
    let processingCount: Int
    var body: some View {
        List(selection: $selection) {
            Label("All Meetings", systemImage: "tray.full").tag(DashboardSelection.allMeetings)
            Label("Needs linking", systemImage: "link.badge.plus")
                .badge(needsLinkingCount).tag(DashboardSelection.needsLinking)
            Label("Processing", systemImage: "gearshape.2")
                .badge(processingCount).tag(DashboardSelection.processing)
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
