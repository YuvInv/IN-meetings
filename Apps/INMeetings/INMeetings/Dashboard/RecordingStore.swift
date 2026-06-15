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

    private let store: MeetingStore?
    init(store: MeetingStore? = try? MeetingStore(url: MeetingStore.defaultURL)) {
        self.store = store
        load()
    }

    func load() { meetings = (try? store?.allMeetings()) ?? [] }

    var filtered: [MeetingRecord] { filterMeetings(meetings, search: search) }

    func meeting(id: String) -> MeetingRecord? { meetings.first { $0.id == id } }
    func transcript(for r: MeetingRecord) -> TranscriptPackage? {
        try? PackageReader.transcript(in: URL(fileURLWithPath: r.folderPath))
    }
    func audioURL(for r: MeetingRecord) -> URL? {
        let u = URL(fileURLWithPath: r.folderPath).appendingPathComponent(PlaybackRenderer.outputName)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}

enum DashboardSelection: Hashable {
    case allMeetings, needsLinking, processing
    case meeting(String)
}
