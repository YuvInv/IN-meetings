import Foundation

/// The folder/upload operations `DriveSync` needs — a protocol so the orchestration is testable with a
/// fake. `DriveClient` is the live implementation.
public protocol DriveUploading: Sendable {
    func findOrCreateFolder(name: String, parentID: String, driveId: String?) async throws -> String
    func uploadFile(name: String, mimeType: String, data: Data, parentID: String, driveId: String?) async throws -> String
    func uploadFileResumable(name: String, mimeType: String, fileURL: URL, parentID: String, driveId: String?) async throws -> String
    func uploadOrReplaceFile(name: String, mimeType: String, data: Data, parentID: String, driveId: String?) async throws -> String
}

extension DriveClient: DriveUploading {}

public struct DriveSyncResult: Sendable {
    public let meetingFolderID: String
    public let uploaded: [String]
}

/// Write-through sync of a finished meeting to Drive (ADR-006): resolve/create `<Company>/<meeting>/`
/// under the user's chosen location, upload the transcript + metadata (one request each) and the
/// recordings (streamed via a resumable session), then mark the index. Idempotent at the meeting level
/// (skips an already-synced meeting).
public final class DriveSync: @unchecked Sendable {
    private let client: DriveUploading
    private let store: MeetingStore

    public init(client: DriveUploading, store: MeetingStore) {
        self.client = client
        self.store = store
    }

    /// Small text files — uploaded in one request each. `summary.md` is written *after* this sync runs
    /// (the saventa-summary auto-trigger fires post-pipeline), so it's skipped here and re-uploaded by
    /// `syncSummary`; listing it keeps any later full re-sync complete.
    static let textFileNames = ["metadata.json", "transcript.json", "transcript.txt", "context.md", "slides_ocr.md", "summary.md"]

    /// The single merged playback artifact, preferred over the raw tracks. A video call muxes into
    /// `meeting.mp4` (video + audio = the whole experience); an audio meeting mixes into `audio.m4a`.
    /// Only when the render produced neither do we fall back to the raw tracks (+ `video.mov` if present).
    static func mediaFileNames(in folder: URL) -> [String] {
        let fm = FileManager.default
        func has(_ n: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(n).path) }
        if has("meeting.mp4") { return ["meeting.mp4"] }
        if has("audio.m4a") { return ["audio.m4a"] }
        var media = ["mic.wav", "system.wav"].filter(has)
        if has("video.mov") { media.append("video.mov") }
        return media
    }

    /// After a successful backup, reclaim local disk by deleting the raw tracks — but only when a merged
    /// playback file (`meeting.mp4` / `audio.m4a`) exists locally (so the dashboard can still play the
    /// meeting). The raw tracks remain in the package on Drive. Video makes recordings GB-scale, so this
    /// is on by default; the user can keep raw tracks via `capture.pruneRawTracksAfterBackup = false`.
    static func pruneRawTracksIfEnabled(in folder: URL, defaults: UserDefaults = .standard) {
        guard CaptureSettings.bool(defaults, CaptureSettings.Keys.pruneRawTracksAfterBackup, default: true)
        else { return }
        let fm = FileManager.default
        func has(_ n: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(n).path) }
        guard has("meeting.mp4") || has("audio.m4a") else { return }   // never prune without a merged file
        for raw in ["mic.wav", "system.wav", "video.mov"] {
            let url = folder.appendingPathComponent(raw)
            if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
        }
    }

    static func mimeType(for name: String) -> String {
        if name.hasSuffix(".json") { return "application/json" }
        if name.hasSuffix(".md") { return "text/markdown" }
        if name.hasSuffix(".wav") { return "audio/wav" }
        if name.hasSuffix(".m4a") { return "audio/mp4" }
        if name.hasSuffix(".mp4") { return "video/mp4" }
        if name.hasSuffix(".mov") { return "video/quicktime" }
        return "text/plain"
    }

    /// Company-first folder name; meetings with no matched company go under a shared `_Unmatched` bucket.
    static func companyFolderName(_ metadata: MeetingMetadata) -> String {
        if let name = metadata.company?.name, !name.isEmpty { return name }
        return "_Unmatched"
    }

    @discardableResult
    public func sync(meetingID: String, packageFolder: URL, into location: DriveLocation,
                     force: Bool = false) async throws -> DriveSyncResult {
        if !force, let record = try store.meeting(id: meetingID),
           record.syncState == "synced", let folderID = record.driveFolderId {
            return DriveSyncResult(meetingFolderID: folderID, uploaded: [])
        }

        let metadata = try PackageReader.metadata(in: packageFolder)
        let companyID = try await client.findOrCreateFolder(
            name: Self.companyFolderName(metadata), parentID: location.folderID, driveId: location.driveID)
        let meetingFolderID = try await client.findOrCreateFolder(
            name: meetingID, parentID: companyID, driveId: location.driveID)

        var uploaded: [String] = []
        for name in Self.textFileNames {
            guard let data = try? Data(contentsOf: packageFolder.appendingPathComponent(name)) else { continue }
            _ = try await client.uploadFile(name: name, mimeType: Self.mimeType(for: name),
                                            data: data, parentID: meetingFolderID, driveId: location.driveID)
            uploaded.append(name)
        }
        for name in Self.mediaFileNames(in: packageFolder) {
            let fileURL = packageFolder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            _ = try await client.uploadFileResumable(name: name, mimeType: Self.mimeType(for: name),
                                                     fileURL: fileURL, parentID: meetingFolderID, driveId: location.driveID)
            uploaded.append(name)
        }

        try store.setSyncState(id: meetingID, driveFolderId: meetingFolderID, syncState: "synced")
        Self.pruneRawTracksIfEnabled(in: packageFolder)   // reclaim disk now the merged file is on Drive
        return DriveSyncResult(meetingFolderID: meetingFolderID, uploaded: uploaded)
    }

    /// Re-upload one summary file to a meeting's existing Drive folder — used after a recipe run writes it
    /// (the main package was already synced when the pipeline finished). `fileName` defaults to `summary.md`
    /// (the mirror of the latest summary, back-compat) but can be a per-recipe `summaries/<recipeId>.md`
    /// subpath; the Drive upload name is the leaf component, so a subpath is **flattened** into the meeting's
    /// Drive folder (the folder already namespaces it — no Drive subfolder round-trip). No-op if the meeting
    /// was never synced (no folder id) or the file is absent. Idempotent (`uploadOrReplaceFile` replaces an
    /// existing copy), so a re-summarize cleanly overwrites.
    @discardableResult
    public func syncSummary(meetingID: String, packageFolder: URL,
                            fileName: String = "summary.md",
                            into location: DriveLocation) async throws -> Bool {
        guard let record = try store.meeting(id: meetingID), let folderID = record.driveFolderId else { return false }
        let url = packageFolder.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return false }
        let driveName = url.lastPathComponent   // flatten any `summaries/<id>.md` subpath to its leaf
        _ = try await client.uploadOrReplaceFile(
            name: driveName, mimeType: Self.mimeType(for: driveName),
            data: data, parentID: folderID, driveId: location.driveID)
        return true
    }
}
