import XCTest
@testable import INMeetingsCore

final class INMeetingsCoreTests: XCTestCase {
    func testVersionIsPresent() {
        XCTAssertFalse(INMeetingsCore.version.isEmpty)
    }
}
