// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our ModelManager (phase/isReady/statusText/retry) for the on-device Hebrew ASR + Silero VAD models; English chrome.
import AppKit
import SwiftUI
import INMeetingsCore

/// Settings → Models: install/verify status for the two on-device models the pipeline needs — the
/// Hebrew ASR GGML (ivrit-turbo) and the Silero VAD. Each row reflects its `ModelManager.phase`: a green
/// "Installed" check when ready, the `statusText` (plus a progress bar while downloading) otherwise, and
/// a Retry button when a download/verify failed.
struct ModelSettingsTab: View {
    var model: ModelManager
    var vad: ModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Models")
                .font(.title2.weight(.semibold))

            VStack(spacing: 0) {
                ModelStatusRow(title: "Hebrew model (ivrit-turbo)",
                               subtitle: "On-device ASR — transcribes the meeting.",
                               manager: model)
                Divider()
                ModelStatusRow(title: "Silero VAD",
                               subtitle: "Voice-activity detection — stops silence hallucination.",
                               manager: vad)
            }
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text("Models install automatically on first launch. Stored at:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(ModelManager.modelsDirectory.path(percentEncoded: false))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ModelManager.modelsDirectory])
                    }
                    .controlSize(.small)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One model's install state. Reads `manager.phase` so it can show the right control per phase
/// (progress bar while downloading, Retry on failure) and `manager.isReady` for the "Installed" check.
private struct ModelStatusRow: View {
    let title: String
    let subtitle: String
    var manager: ModelManager

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            statusAccessory
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusAccessory: some View {
        HStack(spacing: 10) {
            if manager.isReady {
                VStack(alignment: .trailing, spacing: 1) {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                    if let bytes = manager.installedSizeBytes {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                if case .downloading = manager.phase {
                    ProgressView().controlSize(.small)
                }
                if let status = manager.statusText {
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if case .failed = manager.phase {
                    Button("Retry") { manager.retry() }
                }
            }

            Menu {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([manager.fileURL])
                }
                .disabled(!manager.isReady)
                Button("Re-download") { manager.redownload() }
                Divider()
                Button("Delete", role: .destructive) { manager.delete() }
                    .disabled(!manager.isReady)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
