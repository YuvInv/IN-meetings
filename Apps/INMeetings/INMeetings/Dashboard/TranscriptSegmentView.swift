// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.

import SwiftUI
import INMeetingsCore

struct TranscriptSegmentView: View {
    let utterance: TranscriptPackage.Utterance
    let speaker: TranscriptPackage.Speaker?
    let isActive: Bool
    let onTap: () -> Void
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let s = speaker {
                Text((s.name ?? s.id) + ":")
                    .font(.body.weight(.medium))
                    .foregroundStyle(s.side == "internal" ? Color.accentColor : Color.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(utterance.text).font(.body).frame(maxWidth: .infinity, alignment: .leading)
            Text(durationString(utterance.start)).font(.caption.monospacedDigit())
                .foregroundStyle(.secondary).fixedSize()
        }
        .padding(8)
        .background(isActive ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle()).onTapGesture(perform: onTap)
    }
}
