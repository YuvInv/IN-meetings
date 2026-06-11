import XCTest
@testable import INMeetingsCore

@available(macOS 14.2, *)
final class RecordingTests: XCTestCase {
    func testProfileAutoPick() {
        XCTAssertEqual(CaptureProfile.autoPick(callDetected: true), .call)
        XCTAssertEqual(CaptureProfile.autoPick(callDetected: false), .inPerson)
    }

    func testMeetingDirectoryNaming() {
        let comps = DateComponents(year: 2026, month: 6, day: 11, hour: 9, minute: 5, second: 3)
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let dir = RecordingsStore.newMeetingDirectory(now: date)
        XCTAssertEqual(dir.lastPathComponent, "2026-06-11_09-05-03")
        XCTAssertEqual(dir.deletingLastPathComponent().lastPathComponent, "Recordings")
    }
}
