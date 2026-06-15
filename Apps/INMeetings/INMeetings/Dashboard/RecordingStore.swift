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
    private let drive: DriveAuth?
    init(store: MeetingStore? = try? MeetingStore(url: MeetingStore.defaultURL), drive: DriveAuth? = nil) {
        self.store = store
        self.drive = drive
        load()
    }

    func load() { meetings = (try? store?.allMeetings()) ?? [] }

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
