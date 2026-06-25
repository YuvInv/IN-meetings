// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome; side-by-side resizable panes.

import SwiftUI
import AVKit
import AppKit
import INMeetingsCore

struct MeetingDetailView: View {
    let meeting: MeetingRecord
    let store: RecordingStore
    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var observer: Any?
    @State private var isVideo = false
    @State private var isEditingCompany = false
    @State private var draftCompany = ""
    @State private var renamingSpeakerId: String?
    @State private var customName = ""
    // Per-meeting view state, NOT global @AppStorage: the view is identity-scoped per meeting (`.id(id)`
    // in DashboardWindow), so this resets to `true` on every meeting open — a meeting that has a summary
    // always shows it by default, and collapsing it affects only the meeting you're viewing. (A global
    // persisted toggle silently hid the summary on every meeting once turned off — see DECISIONS 2026-06-25.)
    @State private var showSummaryPane = true
    private var pkg: TranscriptPackage? { store.transcript(for: meeting) }

    var body: some View {
        VStack(spacing: 0) {
            header; Divider()
            bodyArea.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !isVideo, player != nil { Divider(); playbackBar }
        }
        .onAppear(perform: configure).onDisappear(perform: teardown)
        .alert("Name this speaker", isPresented: Binding(
            get: { renamingSpeakerId != nil }, set: { if !$0 { renamingSpeakerId = nil } })) {
            TextField("Name", text: $customName)
            Button("Save") {
                if let id = renamingSpeakerId { store.renameSpeaker(customName, email: nil, speakerId: id, for: meeting) }
                renamingSpeakerId = nil
            }
            Button("Cancel", role: .cancel) { renamingSpeakerId = nil }
        }
    }

    /// The split-pane body: a left context column (video + summary) beside the transcript. Collapses to
    /// Summary | Transcript when there is no video, or to a full-width transcript when there is no context
    /// (no video and the summary is hidden or empty) — so no dead pane is ever left behind.
    @ViewBuilder private var bodyArea: some View {
        let showSummary = showSummaryPane && summaryHasContent
        if isVideo {
            ResizableSplit(axis: .horizontal, min0: 240, min1: 320,
                           storageKey: "detail.columnSplit", defaultFraction: 0.38) {
                if showSummary {
                    ResizableSplit(axis: .vertical, min0: 120, min1: 80,
                                   storageKey: "detail.mediaSplit", defaultFraction: 0.55) {
                        videoPane
                    } second: {
                        summaryPane
                    }
                } else {
                    videoPane
                }
            } second: {
                transcriptColumn
            }
        } else if showSummary {
            ResizableSplit(axis: .horizontal, min0: 240, min1: 320,
                           storageKey: "detail.columnSplit", defaultFraction: 0.38) {
                summaryPane
            } second: {
                transcriptColumn
            }
        } else {
            transcriptColumn
        }
    }

    @ViewBuilder private var videoPane: some View {
        if let player {
            PlayerView(player: player).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    /// The right column: speaker chips (when there are utterances) above the transcript scroll.
    @ViewBuilder private var transcriptColumn: some View {
        VStack(spacing: 0) {
            if pkg?.utterances.isEmpty == false {
                speakerLegend.padding(.horizontal).padding(.vertical, 6)
                Divider()
            }
            transcriptArea.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// True when the summary pane has something to show (so the header toggle + the pane appear).
    private var summaryHasContent: Bool {
        switch meeting.summaryState ?? "" {
        case "running", "failed": return true
        case "done": return store.summaryText(for: meeting) != nil
        default: return meeting.status == "transcribed"
        }
    }

    /// A row of speaker chips above the transcript. Each chip is a menu to assign that diarized speaker a
    /// name — one-tap from the meeting's attendees, or a custom name — persisted to transcript.json. (We
    /// can't know which voice is which automatically; that needs voice-ID.)
    @ViewBuilder private var speakerLegend: some View {
        let speakers = pkg?.speakers ?? []
        let attendees = store.metadata(for: meeting)?.attendees ?? []
        HStack(spacing: 8) {
            Image(systemName: "person.2").font(.caption).foregroundStyle(.secondary)
            ForEach(speakers, id: \.id) { sp in
                Menu {
                    ForEach(Array(attendees.enumerated()), id: \.offset) { _, att in
                        Button(att.name) { store.renameSpeaker(att.name, email: att.email, speakerId: sp.id, for: meeting) }
                    }
                    if !attendees.isEmpty { Divider() }
                    Button("Custom name…") { customName = sp.name ?? ""; renamingSpeakerId = sp.id }
                    if sp.name != nil {
                        Button("Reset to “\(sp.id)”", role: .destructive) {
                            store.renameSpeaker(nil, email: nil, speakerId: sp.id, for: meeting)
                        }
                    }
                } label: {
                    Text(sp.name ?? sp.id).font(.caption.weight(.medium))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(sp.side == "internal" ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12),
                            in: Capsule())
            }
            Spacer()
        }
    }

    /// The post-meeting Claude summary (saventa-summary auto-trigger), as a pane that fills its space:
    /// spinner while running; the paste-ready note when done (Copy / Re-summarize); the error + Retry on
    /// failure; or a Summarize button for a transcribed meeting that hasn't been summarized.
    @ViewBuilder private var summaryPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch meeting.summaryState ?? "" {
            case "running":
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Generating summary…").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
            case "done":
                if let text = store.summaryText(for: meeting) {
                    HStack {
                        Label("Summary", systemImage: "sparkles").font(.headline)
                        Spacer()
                        Button { copySummary(text) } label: { Label("Copy", systemImage: "doc.on.doc") }
                            .buttonStyle(.glass).controlSize(.small)
                        Button { store.summarize(meeting) } label: {
                            Label("Re-summarize", systemImage: "arrow.clockwise")
                        }.buttonStyle(.glass).controlSize(.small)
                    }
                    ScrollView {
                        Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            case "failed":
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(meeting.summaryError ?? "Summary failed.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { store.summarize(meeting) }.buttonStyle(.glass).controlSize(.small)
                }
            default:
                if meeting.status == "transcribed" {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundStyle(.secondary)
                        Text("No summary yet.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button { store.summarize(meeting) } label: { Label("Summarize", systemImage: "sparkles") }
                            .buttonStyle(.glassProminent).controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                if isEditingCompany {
                    TextField("Add company", text: $draftCompany)
                        .textFieldStyle(.roundedBorder).font(.title2.weight(.semibold))
                        .frame(maxWidth: 280)
                        .onSubmit { commitCompany() }
                } else {
                    Button {
                        draftCompany = meeting.company ?? ""; isEditingCompany = true
                    } label: {
                        Text(meeting.company?.isEmpty == false ? meeting.company! : "Add company")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(meeting.company?.isEmpty == false ? .primary : .secondary)
                    }.buttonStyle(.plain)
                }
                Text("\(meeting.title ?? "Meeting") · \(durationString(meeting.durationSeconds))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if summaryHasContent {
                Button { showSummaryPane.toggle() } label: { Label("Summary", systemImage: "sparkles") }
                    .buttonStyle(.glass).tint(showSummaryPane ? Color.accentColor : nil)
                    .help(showSummaryPane ? "Hide summary" : "Show summary")
            }
            Button { copyTranscript() } label: { Label("Copy", systemImage: "doc.on.doc") }
                .buttonStyle(.glass)
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: meeting.folderPath)]) }
                label: { Label("Reveal", systemImage: "folder") }.buttonStyle(.glass)
        }.padding()
    }

    @ViewBuilder private var transcriptArea: some View {
        if let us = pkg?.utterances, !us.isEmpty {
            let speakers = Dictionary(uniqueKeysWithValues: (pkg?.speakers ?? []).map { ($0.id, $0) })
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(us.enumerated()), id: \.offset) { i, u in
                        TranscriptSegmentView(utterance: u, speaker: speakers[u.speakerId],
                                              isActive: currentTime >= u.start && currentTime < u.end,
                                              onTap: { seek(to: u.start) })
                    }
                }.padding()
                .environment(\.layoutDirection, pkg?.language == "he" ? .rightToLeft : .leftToRight)
            }
        } else if meeting.status == "failed" {
            ContentUnavailableView {
                Label("Transcription failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(meeting.pipelineError ?? "The pipeline did not finish. See pipeline.log for details.")
            } actions: {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: meeting.folderPath).appendingPathComponent("pipeline.log")])
                } label: { Label("Reveal pipeline.log", systemImage: "doc.text.magnifyingglass") }
                    .buttonStyle(.glass)
            }
        } else {
            ContentUnavailableView("No transcript yet", systemImage: "text.alignleft")
        }
    }

    @ViewBuilder private var playbackBar: some View {
        if let player {
            HStack {
                Button { player.timeControlStatus == .playing ? player.pause() : player.play() }
                    label: { Image(systemName: "play.fill") }.buttonStyle(.glassProminent)
                Slider(value: Binding(get: { currentTime }, set: { seek(to: $0) }),
                       in: 0...max(meeting.durationSeconds ?? 1, 1))
                Text(durationString(currentTime)).monospacedDigit().foregroundStyle(.secondary)
            }.padding()
        }
    }

    private func configure() {
        teardown()
        guard let url = store.playbackURL(for: meeting) else { return }
        isVideo = ["mp4", "mov"].contains(url.pathExtension.lowercased())
        let p = AVPlayer(url: url)
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) {
            currentTime = $0.seconds.isFinite ? $0.seconds : 0
        }
        player = p
    }
    private func teardown() { if let player, let observer { player.removeTimeObserver(observer) }
        observer = nil; player?.pause(); player = nil }
    private func seek(to s: Double) {
        player?.seek(to: CMTime(seconds: s, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = s
    }
    private func copyTranscript() {
        let text = (pkg?.utterances ?? []).map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    private func copySummary(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    private func commitCompany() {
        isEditingCompany = false
        store.setCompany(draftCompany, for: meeting)
    }
}

/// AVKit's AppKit player view wrapped for SwiftUI. We use this instead of SwiftUI's `VideoPlayer`: on this
/// macOS/SDK, realizing `VideoPlayer` aborts the Swift runtime while instantiating `_AVKit_SwiftUI` generic
/// metadata (observed: `getSuperclassMetadata` → `fatalError`, repro'd 3× on opening a video meeting).
/// `AVPlayerView` is a plain `NSView`, so wrapping it ourselves (like the Drive picker's WKWebView) avoids
/// that path entirely — and gives native transport controls for free.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}
