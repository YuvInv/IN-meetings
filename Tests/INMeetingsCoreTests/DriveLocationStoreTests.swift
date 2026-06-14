import XCTest
@testable import INMeetingsCore

final class DriveLocationStoreTests: XCTestCase {
    func testRoundTripsThroughUserDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "qa-\(UUID().uuidString)"))
        let store = DriveLocationStore(defaults: defaults)

        XCTAssertNil(store.load())

        let location = DriveLocation(driveID: "0ASHAREDDRIVE", folderID: "FOLDER", displayName: "IN Meetings (Shared)")
        store.save(location)
        XCTAssertEqual(store.load(), location)

        store.clear()
        XCTAssertNil(store.load())
    }
}
