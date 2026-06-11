import XCTest
@testable import INMeetingsCore

@available(macOS 14.2, *)
final class RecordingTests: XCTestCase {
    func testProfileAutoPick() {
        XCTAssertEqual(CaptureProfile.autoPick(callDetected: true), .call)
        XCTAssertEqual(CaptureProfile.autoPick(callDetected: false), .inPerson)
    }

    @MainActor
    func testStartStopStateMachine() {
        let detector = CallDetector(autoStart: false)   // stays idle, no polling
        let recorder = RecordingController(detector: detector, installHotKey: false)

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.pendingProfile, .inPerson)   // no call detected

        recorder.start()
        guard case .recording(let profile, _) = recorder.state else {
            return XCTFail("expected .recording after start()")
        }
        XCTAssertEqual(profile, .inPerson)

        recorder.stop()
        XCTAssertFalse(recorder.isRecording)
    }
}
