// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.

import SwiftUI

struct DashboardSidebar: View {
    @Binding var selection: DashboardSelection?
    @Binding var search: String
    /// Focus handle for the search field so the ⌘F menu command can focus it (`.searchable` exposes no
    /// focus handle, hence this custom field).
    var searchFocus: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search meetings", text: $search)
                    .textFieldStyle(.plain)
                    .focused(searchFocus)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Clear search")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)

            List(selection: $selection) {
                Label("All Meetings", systemImage: "tray.full").tag(DashboardSelection.allMeetings)
                Label("Queue", systemImage: "clock.arrow.circlepath").tag(DashboardSelection.queue)
            }
            .listStyle(.sidebar)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                SettingsLink { Label("Settings", systemImage: "gear").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(10)
            }
        }
    }
}
