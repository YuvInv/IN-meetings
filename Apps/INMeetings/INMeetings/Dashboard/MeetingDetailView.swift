// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.

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
    private var pkg: TranscriptPackage? { store.transcript(for: meeting) }

    var body: some View {
        VStack(spacing: 0) {
            header; Divider()
            if isVideo, let player {
                PlayerView(player: player)
                    .frame(height: 260)
                Divider()
            }
            transcriptArea.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !isVideo, player != nil { Divider(); playbackBar }
        }
        .onAppear(perform: configure).onDisappear(perform: teardown)
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
