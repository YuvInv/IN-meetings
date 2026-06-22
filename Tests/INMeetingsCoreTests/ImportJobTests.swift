import XCTest
import Foundation
@testable import INMeetingsCore

final class ImportJobTests: XCTestCase {
    func testMakeProducesInPersonSingleTrackImportJob() {
        let iso = ISO8601DateFormatter()
        let start = iso.date(from: "2026-06-22T10:00:00Z")!
        let end = iso.date(from: "2026-06-22T10:30:00Z")!
        let dir = URL(fileURLWithPath: "/tmp/IN Meetings/Recordings/2026-06-22_10-00-00")

        let job = ImportJob.make(meetingId: dir.lastPathComponent, directory: dir,
                                 audioFilename: "audio.wav", startedAt: start, endedAt: end)

        XCTAssertEqual(job["meeting_id"] as? String, "2026-06-22_10-00-00")
        XCTAssertEqual(job["directory"] as? String, dir.path)
        XCTAssertEqual(job["profile"] as? String, "inPerson")
        XCTAssertEqual(job["source"] as? String, "imported")
        XCTAssertEqual(job["video"] as? Bool, false)
        XCTAssertEqual((job["tracks"] as? [String: String])?["mic"], "audio.wav")
        XCTAssertNil((job["tracks"] as? [String: String])?["system"])
        XCTAssertEqual(job["started_at"] as? String, iso.string(from: start))
        XCTAssertEqual(job["ended_at"] as? String, iso.string(from: end))
    }
}
