import XCTest
@testable import INMeetingsCore

/// The Swift→Python job contract (ADR-009): job.json must carry the record-time facts metadata.json
/// needs. Keys here are consumed by `pipeline/job.py` `Job.load`.
@available(macOS 14.2, *)
final class JobBridgeTests: XCTestCase {
    func testMakeJobCarriesRecordTimeFacts() {
        let dir = URL(filePath: "/tmp/2026-06-14_10-00-00")
        let result = CaptureSession.Result(
            profile: .call, directory: dir,
            mic: dir.appendingPathComponent("mic.wav"),
            system: dir.appendingPathComponent("system.wav"),
            micPeakDB: -12, systemPeakDB: -20)

        let job = JobBridge.makeJob(
            result,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 2100),
            captureSourceApp: "us.zoom.xos")

        XCTAssertEqual(job["meeting_id"] as? String, "2026-06-14_10-00-00")
        XCTAssertEqual(job["profile"] as? String, "call")
        XCTAssertEqual(job["capture_source_app"] as? String, "us.zoom.xos")
        XCTAssertEqual((job["tracks"] as? [String: String])?["mic"], "mic.wav")
        XCTAssertEqual((job["tracks"] as? [String: String])?["system"], "system.wav")
        XCTAssertNotNil(job["started_at"])
        XCTAssertNotNil(job["ended_at"])
    }

    func testMakeJobInPersonOmitsSystemTrackAndApp() {
        let dir = URL(filePath: "/tmp/2026-06-14_11-00-00")
        let result = CaptureSession.Result(
            profile: .inPerson, directory: dir,
            mic: dir.appendingPathComponent("mic.wav"),
            system: nil, micPeakDB: -10, systemPeakDB: nil)

        let job = JobBridge.makeJob(result, startedAt: Date(), endedAt: Date(), captureSourceApp: nil)

        XCTAssertEqual(job["profile"] as? String, "inPerson")
        XCTAssertNil((job["tracks"] as? [String: String])?["system"])
        XCTAssertNil(job["capture_source_app"])
    }
}
