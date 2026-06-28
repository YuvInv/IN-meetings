// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome; side-by-side resizable panes.

import SwiftUI
import AVKit
import AppKit
import UniformTypeIdentifiers
import INMeetingsCore

struct MeetingDetailView: View {
    let meeting: MeetingRecord
    let store: RecordingStore
    /// The recorder's bridge — supplies the live phase/progress shown in the header while processing.
    let jobBridge: JobBridge
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
    /// The recipe id of the entry currently shown in the summary pane. nil until first load; set by
    /// `defaultSelectedEntry` on appear + whenever the entry list changes (e.g. after a run finishes).
    @State private var selectedRecipeId: String?
    /// Confirmation presented before deleting a summary.
    @State private var confirmDeleteRecipeId: String?
    /// Confirmation presented before deleting the whole meeting.
    @State private var confirmDeleteMeeting = false
    /// A transcript moment to scroll/seek to, set when the meeting was opened from a search hit.
    @State private var jumpTime: Double?
    /// The utterance index currently being edited inline (nil = no editor open) + its working text.
    @State private var editingUtteranceIndex: Int?
    @State private var editingText = ""
    /// Presents the find-&-replace sheet.
    @State private var showFindReplace = false
    private var pkg: TranscriptPackage? { store.transcript(for: meeting) }

    /// The live processing state for this meeting (nil unless it's currently being processed).
    private var processingState: QueueItemState? {
        guard meeting.status == "processing" else { return nil }
        return QueuePhase.derive(status: meeting.status, pipelinePhase: jobBridge.phase,
                                 pipelineProgress: jobBridge.progress, summaryState: meeting.summaryState,
                                 isActive: meeting.id == jobBridge.activeMeetingID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header; Divider()
            bodyArea.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !isVideo, player != nil { Divider(); playbackBar }
        }
        .onAppear {
            configure()
            syncSelectedEntry()
            // Opened from a transcript search hit → seek the player there; the transcript scrolls via jumpTime.
            if let t = store.consumePendingJump(for: meeting.id) { jumpTime = t; seek(to: t) }
        }
        .onDisappear(perform: teardown)
        // When entries change (a new summary finishes via .summaryDidFinish → store reloads), keep the
        // selected id valid — defaultSelectedEntry will re-seat it or pick a new "done" entry.
        .onChange(of: store.summaryEntries(for: meeting).map(\.id)) { syncSelectedEntry() }
        .alert("Name this speaker", isPresented: Binding(
            get: { renamingSpeakerId != nil }, set: { if !$0 { renamingSpeakerId = nil } })) {
            TextField("Name", text: $customName)
            Button("Save") {
                if let id = renamingSpeakerId { store.renameSpeaker(customName, email: nil, speakerId: id, for: meeting) }
                renamingSpeakerId = nil
            }
            Button("Cancel", role: .cancel) { renamingSpeakerId = nil }
        }
        .alert("Delete summary?", isPresented: Binding(
            get: { confirmDeleteRecipeId != nil }, set: { if !$0 { confirmDeleteRecipeId = nil } })) {
            Button("Delete", role: .destructive) {
                if let id = confirmDeleteRecipeId {
                    if selectedRecipeId == id { selectedRecipeId = nil }
                    store.deleteSummary(meeting, recipeId: id)
                }
                confirmDeleteRecipeId = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteRecipeId = nil }
        } message: {
            Text("This removes the summary from your device. The copy on Drive (if any) is not affected.")
        }
        .alert("Delete meeting?", isPresented: $confirmDeleteMeeting) {
            Button("Delete", role: .destructive) { store.deleteMeeting(meeting) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes this meeting from this Mac. The copy on Google Drive is kept.")
        }
        .sheet(isPresented: Binding(
            get: { editingUtteranceIndex != nil }, set: { if !$0 { editingUtteranceIndex = nil } })) {
            EditUtteranceSheet(text: $editingText, isHebrew: pkg?.language == "he") {
                if let i = editingUtteranceIndex { store.editUtterance(editingText, at: i, for: meeting) }
                editingUtteranceIndex = nil
            } onCancel: { editingUtteranceIndex = nil }
        }
        .sheet(isPresented: $showFindReplace) {
            FindReplaceSheet { find, replaceWith, caseSensitive, learn in
                store.findAndReplaceInTranscript(find: find, replaceWith: replaceWith,
                                                 caseSensitive: caseSensitive, learnCorrection: learn,
                                                 for: meeting)
            }
        }
    }

    /// Keep `selectedRecipeId` in sync after the entry list changes.
    private func syncSelectedEntry() {
        let entries = store.summaryEntries(for: meeting)
        selectedRecipeId = defaultSelectedEntry(current: selectedRecipeId, entries: entries)?.id
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
    /// The pane is also shown on a `"transcribed"` meeting with no summaries yet — so the
    /// "Summarize with…" empty-state CTA is reachable.
    private var summaryHasContent: Bool {
        !store.summaryEntries(for: meeting).isEmpty || meeting.status == "transcribed"
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

    /// The multi-summary pane: a switcher across all summaries for this meeting, a per-meeting
    /// "Summarize with…" run menu, and per-entry Copy / Re-run / Delete actions.
    @ViewBuilder private var summaryPane: some View {
        let entries = store.summaryEntries(for: meeting)
        let selected = entries.first(where: { $0.id == selectedRecipeId }) ?? entries.first
        VStack(alignment: .leading, spacing: 6) {
            if entries.isEmpty {
                // Empty state — transcribed meeting, no summaries yet.
                if meeting.status == "transcribed" {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundStyle(.secondary)
                        Text("No summary yet.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        summarizeMenu(label: "Summarize with…", prominent: true)
                    }
                }
            } else {
                // Top row: switcher + "Summarize with…" add menu + per-entry actions.
                HStack(spacing: 6) {
                    // Switcher — pick which summary to view.
                    Menu {
                        ForEach(entries) { entry in
                            Button {
                                selectedRecipeId = entry.id
                            } label: {
                                Label {
                                    Text(entry.displayName)
                                } icon: {
                                    Image(systemName: stateGlyph(entry.state))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: stateGlyph(selected?.state ?? ""))
                                .foregroundStyle(stateColor(selected?.state ?? ""))
                            Text(selected?.displayName ?? "Summary").fontWeight(.medium)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()

                    Spacer()

                    // Copy the selected summary (shown only when "done" and text is available).
                    if let sel = selected, sel.state == "done",
                       let text = store.summaryText(for: meeting, recipeId: sel.id) {
                        Button { copySummary(text) } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }.buttonStyle(.glass).controlSize(.small)
                    }

                    // Re-run the selected recipe.
                    if let sel = selected {
                        Button {
                            store.summarize(meeting, recipeID: sel.id)
                        } label: {
                            Label("Re-run", systemImage: "arrow.clockwise")
                        }.buttonStyle(.glass).controlSize(.small)
                    }

                    // Delete the selected summary.
                    if let sel = selected {
                        Button(role: .destructive) {
                            confirmDeleteRecipeId = sel.id
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }.buttonStyle(.glass).controlSize(.small)
                    }

                    // "Summarize with…" — run an additional recipe.
                    summarizeMenu(label: "＋", prominent: false)
                }

                Divider()

                // Content area for the selected entry.
                if let sel = selected {
                    switch sel.state {
                    case "running":
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Generating summary…").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                        }
                        Spacer()
                    case "failed":
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            Text(sel.error ?? "Summary failed.").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry") { store.summarize(meeting, recipeID: sel.id) }
                                .buttonStyle(.glass).controlSize(.small)
                        }
                        Spacer()
                    default:
                        if let text = store.summaryText(for: meeting, recipeId: sel.id) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    actionItemsSection(recipeId: sel.id)
                                }
                            }
                        } else {
                            Text("Summary text not found.").font(.callout).foregroundStyle(.secondary)
                            actionItemsSection(recipeId: sel.id)
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The "Summarize with…" dropdown menu. Lists all available recipes; picking one runs it for this
    /// meeting (adding a new summary instead of overwriting).
    @ViewBuilder private func summarizeMenu(label: String, prominent: Bool) -> some View {
        let recipeList = store.recipes()
        if recipeList.isEmpty {
            // No recipes available — fall back to a plain button that runs the default.
            if prominent {
                Button {
                    store.summarize(meeting)
                } label: {
                    Label(label, systemImage: "sparkles")
                }.buttonStyle(.glassProminent).controlSize(.small)
            } else {
                Button {
                    store.summarize(meeting)
                } label: {
                    Label(label, systemImage: "sparkles")
                }.buttonStyle(.glass).controlSize(.small)
            }
        } else {
            Menu {
                ForEach(recipeList) { recipe in
                    Button(recipe.displayName) {
                        store.summarize(meeting, recipeID: recipe.id)
                    }
                }
            } label: {
                Label(label, systemImage: "sparkles")
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()
        }
    }

    /// Read-only checklist of the recipe's structured action items (PR 7), shown below the summary text.
    /// Renders nothing when the recipe didn't emit a sidecar or it has no items — so old runs/recipes
    /// degrade silently.
    @ViewBuilder private func actionItemsSection(recipeId: String) -> some View {
        if let actions = store.actionItems(for: meeting, recipeId: recipeId), !actions.items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                Label("Action Items", systemImage: "checklist").font(.subheadline.weight(.semibold))
                ForEach(Array(actions.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: actionStatusGlyph(item.status))
                            .foregroundStyle(actionStatusColor(item.status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.task).font(.callout)
                            HStack(spacing: 12) {
                                if let owner = item.owner, !owner.isEmpty {
                                    Label(owner, systemImage: "person.fill")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                if let due = item.dueDate, !due.isEmpty {
                                    Label(due, systemImage: "calendar")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// SF Symbol for an action-item status.
    private func actionStatusGlyph(_ status: String) -> String {
        switch status {
        case "done": return "checkmark.circle.fill"
        case "in-progress": return "circle.lefthalf.filled"
        case "blocked": return "exclamationmark.octagon.fill"
        default: return "circle"   // open / unknown
        }
    }

    /// Color for an action-item status glyph.
    private func actionStatusColor(_ status: String) -> Color {
        switch status {
        case "done": return .green
        case "in-progress": return .accentColor
        case "blocked": return .red
        default: return .secondary   // open / unknown
        }
    }

    /// SF Symbol for a summary state glyph in the switcher.
    private func stateGlyph(_ state: String) -> String {
        switch state {
        case "done": return "checkmark.circle.fill"
        case "running": return "arrow.trianglehead.2.clockwise"
        case "failed": return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    /// Accent color for the state glyph.
    private func stateColor(_ state: String) -> Color {
        switch state {
        case "done": return .green
        case "running": return .accentColor
        case "failed": return .orange
        default: return .secondary
        }
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
                if let state = processingState {
                    HStack(spacing: 8) {
                        if let p = state.progress { ProgressView(value: p).frame(width: 120) }
                        Text(state.detailedLabel).font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(meeting.title ?? "Meeting") · \(durationString(meeting.durationSeconds))")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if summaryHasContent {
                Button { showSummaryPane.toggle() } label: { Label("Summary", systemImage: "sparkles") }
                    .buttonStyle(.glass).tint(showSummaryPane ? Color.accentColor : nil)
                    .help(showSummaryPane ? "Hide summary" : "Show summary")
            }
            Button { copyTranscript() } label: { Label("Copy", systemImage: "doc.on.doc") }
                .buttonStyle(.glass)
            if pkg?.utterances.isEmpty == false {
                Button { showFindReplace = true } label: {
                    Label("Find & Replace", systemImage: "text.magnifyingglass")
                }
                .labelStyle(.iconOnly).buttonStyle(.glass)
                .help("Find and replace text across this transcript")
            }
            Menu {
                Button("Export Markdown…") { exportMeeting(asPDF: false) }
                Button("Export PDF…") { exportMeeting(asPDF: true) }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .menuStyle(.button).buttonStyle(.glass).fixedSize()
                .help("Export this meeting as Markdown or PDF")
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: meeting.folderPath)]) }
                label: { Label("Reveal", systemImage: "folder") }.buttonStyle(.glass)
            Button(role: .destructive) { confirmDeleteMeeting = true } label: { Label("Delete", systemImage: "trash") }
                .buttonStyle(.glass).help("Delete this meeting from this Mac")
        }.padding()
    }

    @ViewBuilder private var transcriptArea: some View {
        if let us = pkg?.utterances, !us.isEmpty {
            let speakers = Dictionary(uniqueKeysWithValues: (pkg?.speakers ?? []).map { ($0.id, $0) })
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(us.enumerated()), id: \.offset) { i, u in
                            TranscriptSegmentView(utterance: u, speaker: speakers[u.speakerId],
                                                  isActive: currentTime >= u.start && currentTime < u.end,
                                                  onTap: { seek(to: u.start) },
                                                  onEdit: { editingText = u.text; editingUtteranceIndex = i })
                                .id(i)
                        }
                    }.padding()
                    .environment(\.layoutDirection, pkg?.language == "he" ? .rightToLeft : .leftToRight)
                }
                // Scroll to the matched utterance when opened from a search hit.
                .onChange(of: jumpTime, initial: true) { _, t in
                    guard let t, let idx = activeUtteranceIndex(in: us, at: t) else { return }
                    withAnimation { proxy.scrollTo(idx, anchor: .center) }
                }
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

    /// Export the meeting (transcript + summary + metadata) to a file the user picks. Markdown is written
    /// directly; PDF is rendered from the Core-built HTML (RTL for Hebrew) via an offscreen WKWebView.
    private func exportMeeting(asPDF: Bool) {
        let folder = URL(fileURLWithPath: meeting.folderPath)
        let ext = asPDF ? "pdf" : "md"
        guard let url = savePanelURL(ext: ext) else { return }
        if asPDF {
            guard let html = MeetingExport.html(folder: folder, company: meeting.company,
                                                fallbackTitle: meeting.title,
                                                durationSeconds: meeting.durationSeconds) else { return }
            PDFExporter.write(html: html, to: url)
        } else {
            guard let md = MeetingExport.markdown(folder: folder, company: meeting.company,
                                                  fallbackTitle: meeting.title,
                                                  durationSeconds: meeting.durationSeconds) else { return }
            try? md.data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }

    /// Prompt for a save location, pre-filled with a meeting-derived filename.
    private func savePanelURL(ext: String) -> URL? {
        let panel = NSSavePanel()
        let stem = MeetingExport.filenameStem(company: meeting.company, title: meeting.title,
                                              startedAtISO: meeting.startedAt)
        panel.nameFieldStringValue = "\(stem).\(ext)"
        if let type = UTType(filenameExtension: ext) { panel.allowedContentTypes = [type] }
        return panel.runModal() == .OK ? panel.url : nil
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

/// Inline editor for a single transcript line. RTL for Hebrew so the caret and text behave naturally.
private struct EditUtteranceSheet: View {
    @Binding var text: String
    let isHebrew: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit transcript line").font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(minWidth: 440, minHeight: 140)
                .environment(\.layoutDirection, isHebrew ? .rightToLeft : .leftToRight)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

/// Find & replace across the whole transcript, with an opt-in to remember the correction so future
/// meetings auto-apply it (the pipeline's post-correction reads the learned vocabulary).
private struct FindReplaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var find = ""
    @State private var replaceWith = ""
    @State private var caseSensitive = false
    @State private var learn = false
    @State private var resultCount: Int?
    /// Performs the replacement and returns the number of occurrences replaced.
    let onReplace: (_ find: String, _ replaceWith: String, _ caseSensitive: Bool, _ learn: Bool) -> Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find & Replace").font(.headline)
            Form {
                TextField("Find", text: $find)
                TextField("Replace with", text: $replaceWith)
                Toggle("Case-sensitive", isOn: $caseSensitive)
                Toggle("Remember this correction for future meetings", isOn: $learn)
            }
            if let n = resultCount {
                Text(n == 0 ? "No matches." : "Replaced \(n) occurrence\(n == 1 ? "" : "s").")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Replace All") { resultCount = onReplace(find, replaceWith, caseSensitive, learn) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(find.isEmpty)
            }
        }
        .padding(20).frame(minWidth: 400)
    }
}
