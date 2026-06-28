// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.

import SwiftUI
import INMeetingsCore

struct MeetingListView: View {
    let meetings: [MeetingRecord]
    @Binding var selection: DashboardSelection?
    let store: RecordingStore
    let jobBridge: JobBridge
    /// Meeting pending a delete confirmation (set from the row context menu).
    @State private var pendingDelete: MeetingRecord?

    var body: some View {
        ScrollView {
            listContent
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Delete meeting?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) { if let m = pendingDelete { store.deleteMeeting(m) }; pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Removes this meeting from this Mac. The copy on Google Drive is kept.")
        }
    }

    /// The scroll body: search results, the empty state, or the sort control above the meeting list.
    @ViewBuilder private var listContent: some View {
        if !store.search.trimmingCharacters(in: .whitespaces).isEmpty {
            searchResultsList
        } else if meetings.isEmpty {
            ContentUnavailableView("Nothing here yet", systemImage: "tray",
                                   description: Text("New meetings will appear here."))
                .padding(.top, 60)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                sortControl
                if store.sortOrder == .dateNewest || store.sortOrder == .dateOldest {
                    bucketedList
                } else {
                    flatList
                }
            }
        }
    }

    /// Sort menu — relocated from the top-right toolbar to sit left-aligned above the first day header
    /// ("Today"). Same options and binding as before; re-loads the list when the order changes.
    private var sortControl: some View {
        Menu {
            Picker("Sort", selection: Binding(
                get: { store.sortOrder },
                set: { store.sortOrder = $0; store.load() })) {
                ForEach(MeetingSortOrder.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .fixedSize()
        .help("Sort meetings")
    }

    /// Date-bucketed (Today / Yesterday / …). `bucketMeetingsByDate` is newest-first; for the oldest-first
    /// order we reverse both the bucket order and each bucket's items (without rebuilding the bucket type,
    /// whose memberwise init is internal to the Core module).
    private var bucketedList: some View {
        let buckets = bucketMeetingsByDate(meetings, now: Date())
        let oldestFirst = store.sortOrder == .dateOldest
        let ordered = oldestFirst ? Array(buckets.reversed()) : buckets
        return VStack(alignment: .leading, spacing: 22) {
            ForEach(ordered, id: \.label) { bucket in
                let items = oldestFirst ? Array(bucket.items.reversed()) : bucket.items
                VStack(alignment: .leading, spacing: 6) {
                    Text(bucket.label).font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary).padding(.leading, 4)
                    rowsContainer(items)
                }
            }
        }
    }

    /// Results for the active search query: title/company matches AND full-text transcript hits, each
    /// with an excerpt snippet. Selecting a transcript hit jumps the detail view to that moment.
    private var searchResultsList: some View {
        let results = store.searchResults
        return VStack(alignment: .leading, spacing: 6) {
            if results.isEmpty {
                ContentUnavailableView.search(text: store.search)
                    .padding(.top, 60)
            } else {
                Text(results.count == 1 ? "1 result" : "\(results.count) results")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary).padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(results) { result in
                        SearchResultRow(result: result, isSelected: selection == .meeting(result.meeting.id))
                            .onTapGesture { store.openSearchResult(result) }
                            .contextMenu {
                                Button(role: .destructive) { pendingDelete = result.meeting } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        if result.id != results.last?.id { Divider().padding(.leading, 30) }
                    }
                }
            }
        }
    }

    /// Flat, single-section list for the non-date orders (company / duration / status). The list is
    /// already sorted at the data layer; we render it in order with no date headers.
    private var flatList: some View {
        VStack(alignment: .leading, spacing: 6) {
            rowsContainer(meetings)
        }
    }

    /// Content rows sit on the standard control surface — NOT Liquid Glass. Per the macOS 26 HIG, glass
    /// is for the navigation/chrome layer (toolbars, sidebars, the floating overlays), never for content
    /// lists; a non-glass card here matches the inset Queue list and reads as correctly native.
    @ViewBuilder private func rowsContainer(_ items: [MeetingRecord]) -> some View {
        VStack(spacing: 0) {
            ForEach(items, id: \.id) { m in
                MeetingRow(meeting: m, isSelected: selection == .meeting(m.id), jobBridge: jobBridge)
                    .onTapGesture { selection = .meeting(m.id) }
                    .contextMenu {
                        Button(role: .destructive) { pendingDelete = m } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                if m.id != items.last?.id { Divider().padding(.leading, 36) }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A single search-results row: company/title plus the matched transcript excerpt (when the hit came
/// from inside the meeting), so the user sees *why* it matched before opening.
private struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        let m = result.meeting
        let primary = m.company?.isEmpty == false ? m.company! : (m.title ?? "Untitled")
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: m.type == "in_person" ? "person.wave.2" : "phone")
                    .font(.caption).foregroundStyle(.tint)
                Text(primary).font(.headline).lineLimit(1)
                if let t = m.title, !t.isEmpty, m.company?.isEmpty == false {
                    Text("· \(t)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            if let snippet = result.snippet, !snippet.isEmpty {
                Text(snippet).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}
