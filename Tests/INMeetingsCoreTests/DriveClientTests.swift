import XCTest
@testable import INMeetingsCore

/// The Drive request-building is pure and unit-tested; the live HTTP is verified end to end on sign-in.
final class DriveClientTests: XCTestCase {
    func testFolderQueryForPlainName() {
        XCTAssertEqual(
            DriveClient.folderQuery(name: "Acme", parentID: "PARENT"),
            "name = 'Acme' and 'PARENT' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false")
    }

    func testFolderQueryEscapesApostrophes() {
        XCTAssertTrue(DriveClient.folderQuery(name: "O'Reilly", parentID: "P").contains("name = 'O\\'Reilly'"))
    }

    func testMultipartBodyHasMetadataAndMedia() throws {
        let body = try DriveClient.multipartBody(
            metadata: ["name": "transcript.json"],
            media: Data("{\"x\":1}".utf8),
            mediaType: "application/json",
            boundary: "BOUND")
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(text.hasPrefix("--BOUND\r\n"))
        XCTAssertTrue(text.contains("Content-Type: application/json; charset=UTF-8"))
        XCTAssertTrue(text.contains("\"name\":\"transcript.json\""))
        XCTAssertTrue(text.contains("{\"x\":1}"))
        XCTAssertTrue(text.hasSuffix("--BOUND--\r\n"))
    }

    func testFileQueryEscapesAndScopesToParent() {
        let q = DriveClient.fileQuery(name: "metadata.json", parentID: "FOLDER1")
        XCTAssertTrue(q.contains("name = 'metadata.json'"))
        XCTAssertTrue(q.contains("'FOLDER1' in parents"))
        XCTAssertTrue(q.contains("trashed = false"))
    }

    /// The folder picker resolves a picked folder's Shared Drive via files.get — `driveId` is absent for
    /// My Drive items and present for Shared Drive items.
    func testFileInfoDecodesWithAndWithoutDriveId() throws {
        let shared = try JSONDecoder().decode(
            DriveClient.FileInfo.self, from: Data(#"{"id":"f1","name":"Deals","driveId":"0ASHARED"}"#.utf8))
        XCTAssertEqual(shared.driveId, "0ASHARED")
        XCTAssertEqual(shared.name, "Deals")
        let myDrive = try JSONDecoder().decode(
            DriveClient.FileInfo.self, from: Data(#"{"id":"f2","name":"Notes"}"#.utf8))
        XCTAssertNil(myDrive.driveId)        // My Drive → no driveId
    }
}
