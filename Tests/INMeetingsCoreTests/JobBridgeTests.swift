import XCTest
@testable import INMeetingsCore

/// The Swift→Python job contract (ADR-009): job.json must carry the record-time facts metadata.json
/// needs. Keys here are consumed by `pipeline/job.py` `Job.load`.
/// Also covers the A3 progress-field parsing and `activeMeetingID` exposure (decisions 1+2).
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

    // MARK: - A3: status → observable state (decision 1)
    // `watchStatus`'s parse-and-assign body is extracted into `applyStatus(_:folder:timer:)` so it's
    // testable without a live subprocess. These feed a status payload straight in and assert the
    // *observable* `phase`/`progress` actually update — i.e. the pipeline's `progress` field reaches the
    // UI rather than being silently dropped (the gap the prior JSON-only tests couldn't catch).

    /// A non-terminal status with `progress: 0.35` sets `JobBridge.progress == 0.35` (and `phase`),
    /// and reports non-terminal (false).
    @MainActor
    func testApplyStatusSurfacesProgress() {
        let bridge = JobBridge()
        let terminal = bridge.applyStatus(
            ["phase": "transcribing", "progress": 0.35],
            folder: URL(filePath: "/tmp/meeting"))

        XCTAssertFalse(terminal)
        XCTAssertEqual(bridge.phase, "transcribing")
        let progress = try? XCTUnwrap(bridge.progress)
        XCTAssertEqual(progress ?? -1, 0.35, accuracy: 0.0001)
    }

    /// A status with no `progress` key leaves `progress` nil while still advancing `phase` — a phase
    /// without granular progress (e.g. diarizing just starting) must not carry over a stale fraction.
    @MainActor
    func testApplyStatusMissingProgressIsNil() {
        let bridge = JobBridge()
        _ = bridge.applyStatus(["phase": "transcribing", "progress": 0.5],
                               folder: URL(filePath: "/tmp/meeting"))
        let terminal = bridge.applyStatus(["phase": "diarizing"],
                                          folder: URL(filePath: "/tmp/meeting"))

        XCTAssertFalse(terminal)
        XCTAssertEqual(bridge.phase, "diarizing")
        XCTAssertNil(bridge.progress)
    }

    /// A malformed payload (no `phase`) is ignored — neither `phase` nor `progress` is mutated.
    @MainActor
    func testApplyStatusWithoutPhaseIsIgnored() {
        let bridge = JobBridge()
        _ = bridge.applyStatus(["phase": "packaging", "progress": 0.9],
                               folder: URL(filePath: "/tmp/meeting"))
        let terminal = bridge.applyStatus(["progress": 0.1], folder: URL(filePath: "/tmp/meeting"))

        XCTAssertFalse(terminal)
        XCTAssertEqual(bridge.phase, "packaging")
        XCTAssertEqual(bridge.progress ?? -1, 0.9, accuracy: 0.0001)
    }
}
