import XCTest
@testable import INMeetingsCore

final class DriveBackupTests: XCTestCase {
    private var goldenFixture: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "schema/fixtures/golden-package")
    }

    /// With no connected account, backup is a safe no-op — it must not touch the index or throw.
    func testNoOpWhenNotConfigured() async throws {
        let store = try MeetingStore()
        let record = try store.indexPackage(at: goldenFixture)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "qa-\(UUID().uuidString)"))
        let backup = DriveBackup(meetingStore: store,
                                 tokenStore: InMemoryTokenStore(),
                                 locationStore: DriveLocationStore(defaults: defaults))

        XCTAssertFalse(backup.isConfigured)
        await backup.syncIfConfigured(meetingID: record.id, packageFolder: goldenFixture)

        XCTAssertEqual(try store.meeting(id: record.id)?.syncState, "local")  // unchanged
    }
}
