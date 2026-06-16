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
    @ObservationIgnored private var finishObserver: NSObjectProtocol?
    init(store: MeetingStore? = try? MeetingStore(url: MeetingStore.defaultURL), drive: DriveAuth? = nil) {
        self.store = store
        self.drive = drive
        load()
        // Reload when a pipeline job finishes or fails (JobBridge posts this) so newly-done and failed
        // meetings appear live, without the user reopening the window.
        finishObserver = NotificationCenter.default.addObserver(
            forName: .jobBridgeDidFinish, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.load() }
        }
    }
    deinit { if let finishObserver { NotificationCenter.default.removeObserver(finishObserver) } }

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
}

enum DashboardSelection: Hashable {
    case allMeetings, needsLinking, processing
    case meeting(String)
}
