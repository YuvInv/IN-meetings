import XCTest
@testable import INMeetingsCore

/// Pure logic — drives both the wizard recap and the dashboard "Finish setup" nudge from one source of
/// truth. System Audio has no readable TCC status, so it never appears in `outstanding` and can't gate
/// `isSetUp` (only Microphone + Google form the "usable" floor; Screen Recording is video-only).
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

    func testSystemAudioNeverAppearsInOutstanding() {
        // Even with everything readable granted, System Audio is unreadable and must not be nudged here.
        for s in [snap(mic: true, screen: true, google: true), snap(mic: false, screen: false, google: false)] {
            XCTAssertFalse(OnboardingChecklist.outstanding(s).contains(.systemAudio))
        }
    }
}
