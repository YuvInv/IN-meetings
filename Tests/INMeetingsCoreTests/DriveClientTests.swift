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
}
