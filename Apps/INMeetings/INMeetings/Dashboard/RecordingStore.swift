// Adapted from Mila (github.com/island-io/mila), © Island Technology / Uri Harduf, Apache-2.0. Changes: rebuilt against our MeetingRecord/SQLite index + Liquid Glass; English chrome.

import Foundation
import INMeetingsCore
import Observation

/// Read-only `@Observable` façade over the slice-5 SQLite index + slice-5 PackageReader for the
/// dashboard. Not a port of mila's RecordingStore — our data is the context package + GRDB index.
@MainActor
@Observable
final class RecordingStore {
    private(set) var meetings: [MeetingRecord] = []
    var selection: DashboardSelection? = .allMeetings
    var search: String = ""
    /// The list ordering chosen in the Sort menu; `load()` re-fetches in this order.
    var sortOrder: MeetingSortOrder = .dateNewest
    /// A deferred jump target from a transcript search hit: the detail view seeks + scrolls to this moment.
    var pendingJump: PendingJump?

    private let store: MeetingStore?
    private let drive: DriveAuth?
    /// The recorder's `JobBridge` — used to kick the saventa-summary run for the manual Summarize / Retry
    /// button (the same runner the auto-trigger uses, so runs stay serialized). nil in previews/tests.
    @ObservationIgnored private let jobBridge: JobBridge?
    /// Recipe registry: discovers bundled + user-supplied recipes so the per-meeting run menu and the
    /// summary-entry display names can be resolved without threading the registry through DashboardWindow.
    /// Built from the bundled `skills/` root; nil in previews / unit tests where there is no bundle.
    @ObservationIgnored private let registry: SummaryRecipeRegistry?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    init(store: MeetingStore? = try? MeetingStore(url: MeetingStore.defaultURL),
         drive: DriveAuth? = nil, jobBridge: JobBridge? = nil,
         registry: SummaryRecipeRegistry? = JobBridge.bundledRecipesRootURL().map { SummaryRecipeRegistry(bundledRoot: $0) }) {
        self.store = store
        self.drive = drive
        self.jobBridge = jobBridge
        self.registry = registry
        store?.reconcile()   // self-heal: index any meeting whose completion the watcher missed (relaunch)
        store?.backfillTranscriptSearchIfNeeded()   // one-time: index transcripts that predate the FTS table
        load()
        // Reload when a pipeline job finishes/fails (JobBridge) or a summary completes (SummaryRunner) so
        // newly-done, failed, and summarized meetings appear live without reopening the window.
        for name in [Notification.Name.jobBridgeDidFinish, .summaryDidFinish] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.load() }
            })
        }
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    func load() { meetings = (try? store?.allMeetings(sortBy: sortOrder)) ?? [] }

    /// Delete a meeting from this Mac: its DB rows + the on-disk package folder. The Drive copy is kept
    /// (it's the shared team archive). If the deleted meeting was selected, fall back to All Meetings.
    func deleteMeeting(_ meeting: MeetingRecord) {
        guard let store else { return }
        do {
            try store.deleteMeeting(id: meeting.id)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: meeting.folderPath))
            if selection == .meeting(meeting.id) { selection = .allMeetings }
            load()
        } catch {
            NSLog("deleteMeeting failed: \(error)")
        }
    }

    /// Apply a manual company edit: rewrite metadata.json + index (CompanyEditor), refresh the list, and
    /// (when the meeting is already on Drive) re-upload the corrected metadata.json.
    func setCompany(_ name: String?, for meeting: MeetingRecord) {
        guard let store else { return }
        do {
            let data = try CompanyEditor(store: store).setCompany(name, for: meeting)
            load()
            if let drive, drive.isConnected, let folderID = meeting.driveFolderId {
                Task { await drive.reuploadMetadata(meetingFolderID: folderID, data: data) }
            }
        } catch {
            NSLog("setCompany failed: \(error)")
        }
    }

    /// Generate (or re-generate) the meeting summary — the dashboard's manual Summarize / Retry.
    /// Routed through the recorder's `JobBridge` so it shares the one `SummaryRunner`. The runner
    /// updates the index + posts `.summaryDidFinish`, which reloads this store.
    ///
    /// - Parameter recipeID: When non-nil, use this recipe instead of the user's active-recipe preference
    ///   (per-meeting override, A2 stretch goal).
    func summarize(_ meeting: MeetingRecord, recipeID: String? = nil) {
        jobBridge?.summarize(meetingID: meeting.id, folder: URL(fileURLWithPath: meeting.folderPath),
                             recipeID: recipeID)
    }
    /// The generated summary text (`summary.md`) for a meeting, if it exists.
    func summaryText(for meeting: MeetingRecord) -> String? {
        try? String(contentsOf: URL(fileURLWithPath: meeting.folderPath).appendingPathComponent("summary.md"),
                    encoding: .utf8)
    }

    // MARK: - Multi-summary accessors (T3)

    /// All summaries that exist for a meeting, ordered most-recent-first.
    ///
    /// Uses the Core `makeSummaryEntries` helper (pure, unit-tested). The legacy fallback is handled
    /// there: if the DB returns no rows but `summary.md` exists on disk, a single
    /// `"saventa-summary"` entry is synthesised so older meetings still appear in the switcher.
    func summaryEntries(for meeting: MeetingRecord) -> [SummaryEntry] {
        let folder = URL(fileURLWithPath: meeting.folderPath)
        let rows = (try? store?.summaries(forMeeting: meeting.id)) ?? []
        return makeSummaryEntries(rows: rows, folderURL: folder) { [weak self] id in
            self?.registry?.recipe(id: id)?.displayName ?? humanizeRecipeId(id)
        }
    }

    /// The text for a specific recipe's summary. Reads `summaries/<recipeId>.md`; if absent, falls
    /// back to `summary.md` (covers the legacy + T2 mirror cases).
    func summaryText(for meeting: MeetingRecord, recipeId: String) -> String? {
        let folder = URL(fileURLWithPath: meeting.folderPath)
        let perRecipe = folder.appendingPathComponent("summaries/\(recipeId).md")
        if let text = try? String(contentsOf: perRecipe, encoding: .utf8) { return text }
        // Mirror / legacy fallback.
        return try? String(contentsOf: folder.appendingPathComponent("summary.md"), encoding: .utf8)
    }

    /// Structured action items for a recipe's run (the `summaries/<recipeId>-actions.json` sidecar), or
    /// nil when the recipe didn't emit one (older runs / recipes degrade to no action-items section).
    func actionItems(for meeting: MeetingRecord, recipeId: String) -> ActionItems? {
        ActionItemsLoader.load(forMeetingFolder: URL(fileURLWithPath: meeting.folderPath), recipeId: recipeId)
    }

    /// All available recipes (bundled + user-supplied) for the "Summarize with…" run menu.
    func recipes() -> [SummaryRecipe] { registry?.all() ?? [] }

    /// Delete one recipe's summary and re-establish a coherent post-delete state: remove its DB row + its
    /// on-disk file, recompute the rollup (`meeting.summaryState`), and manage the `summary.md` mirror so
    /// deleting the last summary doesn't leave a phantom legacy entry or a stuck Queue row (see
    /// `reconcileAfterSummaryDelete`). Posting `.summaryDidFinish` reloads this store (the observer's
    /// `load()`) and refreshes any open detail view. Drive copy is left in place (out of scope for T3).
    func deleteSummary(_ meeting: MeetingRecord, recipeId: String) {
        guard let store else { return }
        try? reconcileAfterSummaryDelete(store: store, meetingId: meeting.id, recipeId: recipeId,
                                         folder: URL(fileURLWithPath: meeting.folderPath))
        NotificationCenter.default.post(name: .summaryDidFinish, object: nil)
    }

    var filtered: [MeetingRecord] { filterMeetings(meetings, search: search) }

    /// Search results across BOTH metadata (company/title/id) and transcript bodies (FTS), in the current
    /// sort order. A result carries a `snippet` + `jumpTime` when it matched inside the transcript. Empty
    /// when the search box is empty (callers fall back to the normal list).
    var searchResults: [SearchResult] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let metaIds = Set(filterMeetings(meetings, search: q).map(\.id))
        let hits = (try? store?.searchTranscripts(query: q) ?? []) ?? []
        var firstHit: [String: TranscriptSearchHit] = [:]
        for h in hits where firstHit[h.meetingId] == nil { firstHit[h.meetingId] = h }
        return meetings.compactMap { m in
            let hit = firstHit[m.id]
            guard metaIds.contains(m.id) || hit != nil else { return nil }
            return SearchResult(meeting: m, snippet: hit?.snippet, jumpTime: hit?.startTime)
        }
    }

    /// Open a search result: when it matched inside the transcript, queue a jump to that moment, then select.
    func openSearchResult(_ result: SearchResult) {
        if let t = result.jumpTime { pendingJump = PendingJump(meetingId: result.meeting.id, time: t) }
        selection = .meeting(result.meeting.id)
    }

    /// Return + clear the pending jump time for `id` (set when a transcript search hit was opened).
    func consumePendingJump(for id: String) -> Double? {
        guard pendingJump?.meetingId == id else { return nil }
        let t = pendingJump?.time
        pendingJump = nil
        return t
    }

    func meeting(id: String) -> MeetingRecord? { meetings.first { $0.id == id } }
    func transcript(for r: MeetingRecord) -> TranscriptPackage? {
        try? PackageReader.transcript(in: URL(fileURLWithPath: r.folderPath))
    }
    func metadata(for r: MeetingRecord) -> MeetingMetadata? {
        try? PackageReader.metadata(in: URL(fileURLWithPath: r.folderPath))
    }

    /// Assign (or clear, when `name` is nil) a diarized speaker's display name in transcript.json, refresh
    /// the view, and (when the meeting is on Drive) re-upload the corrected transcript.
    func renameSpeaker(_ name: String?, email: String?, speakerId: String, for meeting: MeetingRecord) {
        do {
            let data = try SpeakerEditor.setName(name, email: email, speakerId: speakerId,
                                                 in: URL(fileURLWithPath: meeting.folderPath))
            load()
            if let drive, drive.isConnected, let folderID = meeting.driveFolderId {
                Task { await drive.reuploadPackageFile("transcript.json", data: data, meetingFolderID: folderID) }
            }
        } catch {
            NSLog("renameSpeaker failed: \(error)")
        }
    }

    /// Edit a single transcript utterance's text: persist to transcript.json, refresh the view + FTS
    /// search index, and (when on Drive) re-upload the corrected transcript. Mirrors `renameSpeaker`.
    func editUtterance(_ newText: String, at index: Int, for meeting: MeetingRecord) {
        let folder = URL(fileURLWithPath: meeting.folderPath)
        do {
            let data = try TranscriptEditor.setUtteranceText(newText, at: index, in: folder)
            store?.reindexTranscriptSearch(meetingId: meeting.id, folder: folder)
            load()
            if let drive, drive.isConnected, let folderID = meeting.driveFolderId {
                Task { await drive.reuploadPackageFile("transcript.json", data: data, meetingFolderID: folderID) }
            }
        } catch {
            NSLog("editUtterance failed: \(error)")
        }
    }

    /// Replace `find` with `replaceWith` across this meeting's transcript (optionally case-sensitive);
    /// when `learnCorrection` is set, also remember it so FUTURE meetings auto-correct (the pipeline reads
    /// the same vocab file). Persists, refreshes the view + FTS, re-uploads to Drive. Returns the count.
    @discardableResult
    func findAndReplaceInTranscript(find: String, replaceWith: String, caseSensitive: Bool,
                                    learnCorrection: Bool, for meeting: MeetingRecord) -> Int {
        let folder = URL(fileURLWithPath: meeting.folderPath)
        do {
            let (data, count) = try TranscriptEditor.findAndReplace(
                find: find, replaceWith: replaceWith, caseSensitive: caseSensitive, in: folder)
            guard count > 0 else { return 0 }
            if learnCorrection { try? VocabStore().learn(canonical: replaceWith, variant: find) }
            store?.reindexTranscriptSearch(meetingId: meeting.id, folder: folder)
            load()
            if let drive, drive.isConnected, let folderID = meeting.driveFolderId {
                Task { await drive.reuploadPackageFile("transcript.json", data: data, meetingFolderID: folderID) }
            }
            return count
        } catch {
            NSLog("findAndReplaceInTranscript failed: \(error)")
            return 0
        }
    }

    /// The merged playback file for a meeting: the muxed video (`meeting.mp4`) if present, else the mixed
    /// audio (`audio.m4a`). nil until the renderer has produced one.
    func playbackURL(for r: MeetingRecord) -> URL? {
        let folder = URL(fileURLWithPath: r.folderPath)
        for name in [PlaybackRenderer.videoOutputName, PlaybackRenderer.outputName] {
            let u = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    // MARK: - Calendar import passthroughs

    /// Calendar event ids that already have a recording (panel "✓ recorded" markers).
    func recordedCalendarEventIds() -> Set<String> {
        (try? store?.calendarEventIdsWithRecording()) ?? []
    }

    /// Open the meeting bound to a calendar event (panel click-through).
    func openMeeting(forCalendarEventId eventId: String) {
        if let m = try? store?.meeting(forCalendarEventId: eventId) { selection = .meeting(m.id) }
    }

    /// Surfaced as an alert by the dashboard when an import fails before processing.
    var importError: String?

    /// Import a recording (optionally bound to a calendar event) and select it once processing starts.
    /// Reloads the list when the pipeline finishes (the existing `.jobBridgeDidFinish` observer covers it).
    func importRecording(from fileURL: URL, event: CalendarEvent?, start: Date, end: Date) async {
        // JobBridge is a shared singleton with one watch timer; enqueueImport while a job is in flight would
        // invalidate the live job's status watcher and orphan its indexing/Drive sync. Refuse until idle.
        if let phase = jobBridge?.phase, phase != "done", phase != "failed" {
            importError = "A recording is still being processed. Please wait for it to finish, then import."
            return
        }
        let importer = MeetingImporter(
            writePinnedContext: { dir, ev, s, e in CalendarContext().writePinnedInput(into: dir, event: ev, startedAt: s, endedAt: e) },
            enqueue: { [weak self] dir, name, s, e in self?.jobBridge?.enqueueImport(directory: dir, audioFilename: name, startedAt: s, endedAt: e) })
        do {
            let id = try await importer.importRecording(from: fileURL, event: event, start: start, end: end)
            load()
            selection = .meeting(id)
        } catch {
            importError = error.localizedDescription
        }
    }
}

enum DashboardSelection: Hashable {
    case allMeetings
    case queue
    case meeting(String)
}

/// One row in the search-results list: the meeting plus, when matched inside the transcript, an excerpt
/// snippet and the time to jump to.
struct SearchResult: Identifiable {
    let meeting: MeetingRecord
    let snippet: String?
    let jumpTime: Double?
    var id: String { meeting.id }
}

/// A pending transcript jump: the detail view seeks the player to `time` and scrolls the transcript there.
struct PendingJump {
    let meetingId: String
    let time: Double
}

// MARK: - Private helpers

/// Humanize a kebab-case recipe id into a display name, e.g. `"saventa-summary"` → `"Saventa Summary"`.
/// Used as a fallback when the registry doesn't know the id.
private func humanizeRecipeId(_ id: String) -> String {
    id.split(separator: "-")
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
}
