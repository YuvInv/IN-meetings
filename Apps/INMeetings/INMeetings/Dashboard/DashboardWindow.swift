// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.

import SwiftUI
import INMeetingsCore

struct DashboardWindow: View {
    let drive: DriveAuth
    @State private var storeModel: RecordingStore
    init(drive: DriveAuth) {
        self.drive = drive
        _storeModel = State(initialValue: RecordingStore(drive: drive))
    }
    var body: some View {
        NavigationSplitView {
            DashboardSidebar(selection: $storeModel.selection,
                             needsLinkingCount: needsLinking(storeModel.meetings).count,
                             processingCount: processing(storeModel.meetings).count)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            content
        }
        .searchable(text: $storeModel.search, placement: .toolbar, prompt: "Search meetings")
        .onAppear { storeModel.load() }
    }
    @ViewBuilder private var content: some View {
        switch storeModel.selection ?? .allMeetings {
        case .allMeetings:  MeetingListView(meetings: storeModel.filtered, selection: $storeModel.selection)
        case .needsLinking: MeetingListView(meetings: needsLinking(storeModel.filtered), selection: $storeModel.selection)
        case .processing:   MeetingListView(meetings: processing(storeModel.filtered), selection: $storeModel.selection)
        case .meeting(let id):
            if let m = storeModel.meeting(id: id) { MeetingDetailView(meeting: m, store: storeModel).id(id) }
            else { ContentUnavailableView("Meeting not found", systemImage: "questionmark.folder") }
        }
    }
}
