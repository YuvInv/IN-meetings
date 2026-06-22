// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.

import SwiftUI
import UniformTypeIdentifiers
import INMeetingsCore

struct DashboardWindow: View {
    let drive: DriveAuth
    let jobBridge: JobBridge
    @State private var storeModel: RecordingStore
    @State private var calendarModel: CalendarPanelModel
    @AppStorage("showCalendarPanel") private var showCalendar = false
    @State private var importing = false
    @State private var pendingEvent: CalendarEvent?

    init(drive: DriveAuth, jobBridge: JobBridge) {
        self.drive = drive
        self.jobBridge = jobBridge
        let store = RecordingStore(drive: drive, jobBridge: jobBridge)
        _storeModel = State(initialValue: store)
        _calendarModel = State(initialValue: CalendarPanelModel(
            calendar: CalendarContext(),
            recordedIds: { [weak store] in store?.recordedCalendarEventIds() ?? [] }))
    }

    var body: some View {
        NavigationSplitView {
            DashboardSidebar(selection: $storeModel.selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            content
                .searchable(text: $storeModel.search, placement: .toolbar, prompt: "Search meetings")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCalendar.toggle() } label: {
                    Label("Calendar", systemImage: showCalendar ? "sidebar.right" : "calendar")
                }
                .help(showCalendar ? "Hide calendar" : "Show calendar")
            }
        }
        .inspector(isPresented: $showCalendar) {
            CalendarPanel(drive: drive, model: calendarModel,
                          onUpload: { event in pendingEvent = event; importing = true },
                          onOpenRecorded: { event in storeModel.openMeeting(forCalendarEventId: event.id) })
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.audio, .movie, .mpeg4Movie, .quickTimeMovie],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .alert("Import failed", isPresented: Binding(
            get: { storeModel.importError != nil },
            set: { if !$0 { storeModel.importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(storeModel.importError ?? "") }
        .onAppear { storeModel.load() }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let event = pendingEvent
        pendingEvent = nil                       // clear synchronously, before the async work
        let (start, end) = Self.window(for: event)
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            await storeModel.importRecording(from: url, event: event, start: start, end: end)
        }
    }

    /// The meeting window: the event's start/end when bound, else "now" (no-event import).
    static func window(for event: CalendarEvent?) -> (Date, Date) {
        let iso = ISO8601DateFormatter()
        if let event,
           let s = event.start.dateTime.flatMap({ iso.date(from: $0) }),
           let e = event.end.dateTime.flatMap({ iso.date(from: $0) }) { return (s, e) }
        let now = Date()
        return (now, now)
    }

    @ViewBuilder private var content: some View {
        switch storeModel.selection ?? .allMeetings {
        case .allMeetings:  MeetingListView(meetings: storeModel.filtered, selection: $storeModel.selection)
        case .meeting(let id):
            if let m = storeModel.meeting(id: id) { MeetingDetailView(meeting: m, store: storeModel).id(id) }
            else { ContentUnavailableView("Meeting not found", systemImage: "questionmark.folder") }
        }
    }
}
