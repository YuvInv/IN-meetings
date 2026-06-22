import XCTest
@testable import INMeetingsCore

/// Pure logic — drives both the wizard recap and the dashboard "Finish setup" nudge from one source of
/// truth. Only Microphone + Google form the "usable" floor; Screen & System Audio Recording is needed for
/// the "Them" track + video but doesn't gate `isSetUp`.
final class OnboardingChecklistTests: XCTestCase {
    private func snap(mic: Bool, screen: Bool, google: Bool) -> PermissionsSnapshot {
        PermissionsSnapshot(micGranted: mic, screenGranted: screen, googleConnected: google)
    }

    func testAllGranted() {
        let s = snap(mic: true, screen: true, google: true)
        XCTAssertEqual(OnboardingChecklist.outstanding(s), [])
        XCTAssertTrue(OnboardingChecklist.isSetUp(s))
    }

    func testNothingGranted() {
        let s = snap(mic: false, screen: false, google: false)
        XCTAssertEqual(OnboardingChecklist.outstanding(s), [.microphone, .screenRecording, .google])
        XCTAssertFalse(OnboardingChecklist.isSetUp(s))
    }

    func testScreenRecordingIsOptionalForTheUsableFloor() {
        // Mic + Google connected but no Screen Recording → usable (audio-only), but still nudge for video.
        let s = snap(mic: true, screen: false, google: true)
        XCTAssertEqual(OnboardingChecklist.outstanding(s), [.screenRecording])
        XCTAssertTrue(OnboardingChecklist.isSetUp(s))
    }

    func testMissingMicIsNotSetUp() {
        let s = snap(mic: false, screen: true, google: true)
        XCTAssertEqual(OnboardingChecklist.outstanding(s), [.microphone])
        XCTAssertFalse(OnboardingChecklist.isSetUp(s))
    }

    func testMissingGoogleIsNotSetUp() {
        let s = snap(mic: true, screen: true, google: false)
        XCTAssertEqual(OnboardingChecklist.outstanding(s), [.google])
        XCTAssertFalse(OnboardingChecklist.isSetUp(s))
    }
}
