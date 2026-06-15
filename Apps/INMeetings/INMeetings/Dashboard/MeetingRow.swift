// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.

import SwiftUI
import INMeetingsCore

struct MeetingRow: View {
    let meeting: MeetingRecord
    let isSelected: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: meeting.type == "in_person" ? "person.wave.2" : "phone")
                .foregroundStyle(.tint).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meeting.company?.isEmpty == false ? meeting.company! : "Unknown company")
                        .font(.headline).lineLimit(1)
                    if let t = meeting.title, !t.isEmpty {
                        Text("· \(t)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(durationString(meeting.durationSeconds))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    chip(meeting.type == "in_person" ? "in-person" : "call", "phone", .secondary)
                    if meeting.status == "failed" { chip("failed", "exclamationmark.triangle.fill", .red) }
                    if meeting.syncState == "synced" { chip("synced", "cloud.fill", .green) }
                    if meeting.biased { chip("context", "sparkles", .blue) }
                    if meeting.status != "failed" && (meeting.company ?? "").isEmpty {
                        chip("link?", "link", .orange)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
    private func chip(_ t: String, _ icon: String, _ color: Color) -> some View {
        Label(t, systemImage: icon).font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule()).foregroundStyle(color)
    }
}
func durationString(_ s: Double?) -> String {
    let t = Int((s ?? 0).rounded()); return t >= 3600
        ? String(format: "%d:%02d:%02d", t/3600, (t%3600)/60, t%60)
        : String(format: "%d:%02d", t/60, t%60)
}
