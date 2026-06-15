// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.

import SwiftUI
import INMeetingsCore

struct MeetingListView: View {
    let meetings: [MeetingRecord]
    @Binding var selection: DashboardSelection?
    var body: some View {
        let buckets = bucketMeetingsByDate(meetings, now: Date())
        ScrollView {
            if meetings.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "tray",
                                       description: Text("New meetings will appear here."))
                    .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(buckets, id: \.label) { bucket in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(bucket.label).font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary).padding(.leading, 4)
                            GlassEffectContainer {
                                VStack(spacing: 0) {
                                    ForEach(bucket.items, id: \.id) { m in
                                        MeetingRow(meeting: m, isSelected: selection == .meeting(m.id))
                                            .onTapGesture { selection = .meeting(m.id) }
                                        if m.id != bucket.items.last?.id { Divider().padding(.leading, 36) }
                                    }
                                }
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}
