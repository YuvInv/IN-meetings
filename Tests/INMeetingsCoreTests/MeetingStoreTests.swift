import XCTest
@testable import INMeetingsCore

/// The SQLite index (ADR-006): indexing a finished package folder yields a queryable row.
final class MeetingStoreTests: XCTestCase {
    private var fixture: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // INMeetingsCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appending(path: "schema/fixtures/golden-package")
    }

    func testIndexGoldenPackageInsertsRow() throws {
        let store = try MeetingStore()  // in-memory
        let rec = try store.indexPackage(at: fixture)

        XCTAssertEqual(rec.id, "golden-package")  // folder name is the local meeting id
        XCTAssertEqual(rec.company, "Prelligence")
        XCTAssertEqual(rec.title, "Prelligence — Series A intro")
        XCTAssertEqual(rec.type, "call")
        XCTAssertEqual(rec.speakerCount, 2)
        XCTAssertTrue(rec.diarized)
        XCTAssertTrue(rec.biased)
        XCTAssertEqual(rec.consentStatus, "verbal")
        XCTAssertEqual(rec.syncState, "local")
        XCTAssertNil(rec.driveFolderId)
    }

    func testIndexIsIdempotent() throws {
        let store = try MeetingStore()
        _ = try store.indexPackage(at: fixture)
        _ = try store.indexPackage(at: fixture)
        XCTAssertEqual(try store.allMeetings().count, 1)
    }

    func testFetchByIdRoundTrips() throws {
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: fixture)

        let fetched = try store.meeting(id: rec.id)
        XCTAssertEqual(fetched?.company, "Prelligence")
        XCTAssertEqual(fetched?.startedAt, "2026-05-12T14:30:00+03:00")
        XCTAssertEqual(fetched?.modelRevision, "ivrit-large-v3-turbo")
    }
}
