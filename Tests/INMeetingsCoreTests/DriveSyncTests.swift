import XCTest
@testable import INMeetingsCore

/// Records the folder/upload calls so we can assert the company-first layout + idempotency without HTTP.
private final class FakeUploader: DriveUploading, @unchecked Sendable {
    var folderRequests: [String] = []
    var uploadedNames: [String] = []

    func findOrCreateFolder(name: String, parentID: String, driveId: String?) async throws -> String {
        folderRequests.append(name)
        return "folder:\(name)"
    }

    func uploadFile(name: String, mimeType: String, data: Data, parentID: String, driveId: String?) async throws -> String {
        uploadedNames.append(name)
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

        // company folder first, then the meeting folder under it
        XCTAssertEqual(fake.folderRequests, ["Prelligence", record.id])
        // the four text files in the golden package (no slides_ocr.md / wavs)
        XCTAssertEqual(Set(fake.uploadedNames), ["metadata.json", "transcript.json", "transcript.txt", "context.md"])
        XCTAssertEqual(result.meetingFolderID, "folder:\(record.id)")

        let updated = try store.meeting(id: record.id)
        XCTAssertEqual(updated?.syncState, "synced")
        XCTAssertEqual(updated?.driveFolderId, "folder:\(record.id)")
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
        XCTAssertEqual(fake.uploadedNames.count, uploadsAfterFirst)  // no re-upload
    }
}
