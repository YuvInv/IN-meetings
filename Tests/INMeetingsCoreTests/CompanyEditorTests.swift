import XCTest
@testable import INMeetingsCore

final class CompanyEditorTests: XCTestCase {
    private var goldenDir: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "schema/fixtures/golden-package")
    }

    /// Copy the golden package to a temp dir so we can mutate its metadata.json.
    private func tempPackage() throws -> URL {
        let dst = FileManager.default.temporaryDirectory.appending(path: "ce-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: goldenDir, to: dst)
        return dst
    }

    func testSetCompanyRewritesMetadataAndIndex() throws {
        let dir = try tempPackage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)

        _ = try CompanyEditor(store: store).setCompany("Acme AI", for: rec)

        // SQLite updated
        XCTAssertEqual(try store.meeting(id: rec.id)?.company, "Acme AI")
        // metadata.json updated, other keys preserved
        let data = try Data(contentsOf: dir.appending(path: "metadata.json"))
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let company = root["company"] as! [String: Any]
        XCTAssertEqual(company["name"] as? String, "Acme AI")
        XCTAssertEqual(company["source"] as? String, "user")
        XCTAssertEqual((root["meeting"] as? [String: Any])?["type"] as? String, "call")  // untouched
    }

    func testClearCompanyWritesNull() throws {
        let dir = try tempPackage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)

        _ = try CompanyEditor(store: store).setCompany("   ", for: rec)  // blank → clear

        XCTAssertNil(try store.meeting(id: rec.id)?.company)
        let root = try JSONSerialization.jsonObject(
            with: Data(contentsOf: dir.appending(path: "metadata.json"))) as! [String: Any]
        XCTAssertTrue((root["company"] as! [String: Any])["name"] is NSNull)
    }
}
