import SwiftUI
import INMeetingsCore

/// Dedicated Queue / Processing view: shows every meeting that is in-flight, failed, or finishing
/// its summary. Each row carries the live pipeline phase, a progress bar, and — on failure — a
/// "Reveal pipeline.log" button and a Retry button (A3).
struct QueueView: View {
    @State var model: QueueModel
    let store: RecordingStore
    let jobBridge: JobBridge

    var body: some View {
        Group {
            if model.items.isEmpty {
                ContentUnavailableView(
                    "No active jobs",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Meetings being processed will appear here."))
            } else {
                List(model.items) { item in
                    QueueRowView(item: item, store: store, jobBridge: jobBridge)
                        .listRowSeparator(.visible)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Queue")
        .onAppear { model.reload() }
    }
}

// MARK: - Row

private struct QueueRowView: View {
    let item: QueueItem
    let store: RecordingStore
    let jobBridge: JobBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title / company
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.meeting.company ?? item.meeting.title ?? item.meeting.id)
                        .font(.headline)
                    if let title = item.meeting.title, item.meeting.company != nil {
                        Text(title).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(item.state.label)
                    .font(.caption)
                    .foregroundStyle(labelColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(labelColor.opacity(0.12), in: .capsule)
            }

            // Progress bar — only for phases that carry granular progress
            if let p = item.state.progress {
                ProgressView(value: p).tint(.accentColor)
            } else if item.state == .queued || item.state == .summarizing {
                ProgressView().progressViewStyle(.linear)
            }

            // Failure actions
            if item.state == .failed {
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: item.meeting.folderPath)
                                .appendingPathComponent("pipeline.log")])
                    } label: {
                        Label("Reveal pipeline.log", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.glass)

                    Button {
                        jobBridge.retry(folder: URL(fileURLWithPath: item.meeting.folderPath))
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glassProminent)
                }
            }

            // Summary failure action
            if item.state == .summaryFailed {
                Button {
                    store.summarize(item.meeting)
                } label: {
                    Label("Retry summary", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glassProminent)
            }

            // Pipeline error text for failed rows
            if item.state == .failed, let err = item.meeting.pipelineError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var labelColor: Color {
        switch item.state {
        case .failed, .summaryFailed: return .red
        case .done:                   return .green
        case .queued:                 return .secondary
        default:                      return .accentColor
        }
    }
}
