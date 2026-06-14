import Foundation

/// The folder/upload operations `DriveSync` needs — a protocol so the orchestration is testable with a
/// fake. `DriveClient` is the live implementation.
public protocol DriveUploading: Sendable {
    func findOrCreateFolder(name: String, parentID: String, driveId: String?) async throws -> String
    func uploadFile(name: String, mimeType: String, data: Data, parentID: String, driveId: String?) async throws -> String
    func uploadFileResumable(name: String, mimeType: String, fileURL: URL, parentID: String, driveId: String?) async throws -> String
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

    /// Small text files — uploaded in one request each.
    static let textFileNames = ["metadata.json", "transcript.json", "transcript.txt", "context.md", "slides_ocr.md"]
    /// Recordings — streamed from disk via a resumable session (can be hundreds of MB).
    static let mediaFileNames = ["mic.wav", "system.wav", "video.mov"]

    static func mimeType(for name: String) -> String {
        if name.hasSuffix(".json") { return "application/json" }
        if name.hasSuffix(".md") { return "text/markdown" }
        if name.hasSuffix(".wav") { return "audio/wav" }
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
        for name in Self.mediaFileNames {
            let fileURL = packageFolder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            _ = try await client.uploadFileResumable(name: name, mimeType: Self.mimeType(for: name),
                                                     fileURL: fileURL, parentID: meetingFolderID, driveId: location.driveID)
            uploaded.append(name)
        }

        try store.setSyncState(id: meetingID, driveFolderId: meetingFolderID, syncState: "synced")
        return DriveSyncResult(meetingFolderID: meetingFolderID, uploaded: uploaded)
    }
}
