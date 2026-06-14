import XCTest
@testable import INMeetingsCore

/// Records the folder/upload calls so we can assert the company-first layout, the text-vs-resumable
/// routing, and idempotency — all without real HTTP.
private final class FakeUploader: DriveUploading, @unchecked Sendable {
    var folderRequests: [String] = []
    var uploadedNames: [String] = []      // one-shot (text)
    var resumableUploads: [String] = []   // streamed (recordings)

    func findOrCreateFolder(name: String, parentID: String, driveId: String?) async throws -> String {
        folderRequests.append(name)
        return "folder:\(name)"
    }

    func uploadFile(name: String, mimeType: String, data: Data, parentID: String, driveId: String?) async throws -> String {
        uploadedNames.append(name)
        return "file:\(name)"
    }

    func uploadFileResumable(name: String, mimeType: String, fileURL: URL, parentID: String, driveId: String?) async throws -> String {
        resumableUploads.append(name)
        return "file:\(name)"
    }
}

final class DriveSyncTests: XCTestCase {
    private var goldenFixture: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "schema/fixtures/golden-package")
    }

    private let location = DriveLocation(driveID: "0ASHAREDDRIVE", folderID: "BASE", displayName: "Test")

    func testCompanyFolderNameFallsBackToUnmatched() throws {
        let m = try PackageReader.metadata(in: goldenFixture)
        XCTAssertEqual(DriveSync.companyFolderName(m), "Prelligence")
    }

    func testSyncBuildsCompanyFirstLayoutAndUploadsTextPackage() async throws {
        let store = try MeetingStore()
        let record = try store.indexPackage(at: goldenFixture)
        let fake = FakeUploader()
        let sync = DriveSync(client: fake, store: store)

        let result = try await sync.sync(meetingID: record.id, packageFolder: goldenFixture, into: location)

        XCTAssertEqual(fake.folderRequests, ["Prelligence", record.id])          // company, then meeting
        XCTAssertEqual(Set(fake.uploadedNames), ["metadata.json", "transcript.json", "transcript.txt", "context.md"])
        XCTAssertTrue(fake.resumableUploads.isEmpty)                             // the fixture has no recordings
        XCTAssertEqual(result.meetingFolderID, "folder:\(record.id)")

        let updated = try store.meeting(id: record.id)
        XCTAssertEqual(updated?.syncState, "synced")
    }

    func testSyncUploadsRecordingsViaResumable() async throws {
        let store = try MeetingStore()
        let fake = FakeUploader()
        let sync = DriveSync(client: fake, store: store)

        // A package folder: the text files (from the fixture) + dummy recordings.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["metadata.json", "transcript.json", "transcript.txt", "context.md"] {
            try FileManager.default.copyItem(at: goldenFixture.appendingPathComponent(name),
                                             to: dir.appendingPathComponent(name))
        }
        try Data("RIFFmic".utf8).write(to: dir.appendingPathComponent("mic.wav"))
        try Data("RIFFsys".utf8).write(to: dir.appendingPathComponent("system.wav"))

        let record = try store.indexPackage(at: dir)
        _ = try await sync.sync(meetingID: record.id, packageFolder: dir, into: location)

        XCTAssertEqual(Set(fake.resumableUploads), ["mic.wav", "system.wav"])    // recordings → resumable
        XCTAssertTrue(fake.uploadedNames.contains("transcript.txt"))            // readable transcript → one-shot
        XCTAssertTrue(fake.uploadedNames.contains("metadata.json"))
    }

    func testSyncIsIdempotentOnceSynced() async throws {
        let store = try MeetingStore()
        let record = try store.indexPackage(at: goldenFixture)
        let fake = FakeUploader()
        let sync = DriveSync(client: fake, store: store)

        _ = try await sync.sync(meetingID: record.id, packageFolder: goldenFixture, into: location)
        let uploadsAfterFirst = fake.uploadedNames.count

        let second = try await sync.sync(meetingID: record.id, packageFolder: goldenFixture, into: location)
        XCTAssertTrue(second.uploaded.isEmpty)
        XCTAssertEqual(fake.uploadedNames.count, uploadsAfterFirst)
    }
}
