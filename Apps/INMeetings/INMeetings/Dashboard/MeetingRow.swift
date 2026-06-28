// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.

import SwiftUI
import INMeetingsCore

struct MeetingRow: View {
    let meeting: MeetingRecord
    let isSelected: Bool
    /// The recorder's bridge — supplies the live phase/progress of the active job (determinate bar).
    let jobBridge: JobBridge
    var body: some View {
        let isProcessing = meeting.status == "processing"
        // When this meeting is the one the pipeline is actively running, show its determinate phase +
        // progress (matching the Queue view); other processing rows render as an indeterminate "Queued".
        let state: QueueItemState? = isProcessing ? QueuePhase.derive(
            status: meeting.status, pipelinePhase: jobBridge.phase, pipelineProgress: jobBridge.progress,
            summaryState: meeting.summaryState, isActive: meeting.id == jobBridge.activeMeetingID) : nil
        return HStack(alignment: .top, spacing: 12) {
            Group {
                if isProcessing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: meeting.type == "in_person" ? "person.wave.2" : "phone")
                        .foregroundStyle(.tint)
                }
            }
            .frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(isProcessing && (meeting.company ?? "").isEmpty ? "Processing…"
                         : (meeting.company?.isEmpty == false ? meeting.company! : "Unknown company"))
                        .font(.headline).lineLimit(1)
                    if let t = meeting.title, !t.isEmpty {
                        Text("· \(t)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let state {
                        Text(state.detailedLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    } else if !isProcessing {
                        Text(durationString(meeting.durationSeconds))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if let p = state?.progress {
                    ProgressView(value: p).controlSize(.small)
                }
                HStack(spacing: 6) {
                    chip(meeting.type == "in_person" ? "in-person" : "call", "phone", .secondary)
                    if meeting.source == "imported" {
                        Text("Imported").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.tint.opacity(0.15), in: Capsule()).foregroundStyle(.tint)
                    }
                    if isProcessing { chip("processing", "gearshape.2", .blue) }
                    if meeting.status == "failed" { chip("failed", "exclamationmark.triangle.fill", .red) }
                    if meeting.syncState == "synced" { chip("synced", "cloud.fill", .green) }
                    if meeting.biased { chip("context", "sparkles", .blue) }
                    if !isProcessing && meeting.status != "failed" && (meeting.company ?? "").isEmpty {
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
