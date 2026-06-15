import XCTest
@testable import INMeetingsCore

@MainActor
final class CaptureSettingsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "caps-\(UUID().uuidString)")! }

    func testDefaultsAreOnFirstLaunch() {
        let s = CaptureSettings(defaults: freshDefaults())
        XCTAssertTrue(s.recordCallVideo)              // video on by default for calls
        XCTAssertTrue(s.pruneRawTracksAfterBackup)    // reclaim disk by default
    }

    func testChangesPersistAcrossReload() {
        let d = freshDefaults()
        let s = CaptureSettings(defaults: d)
        s.recordCallVideo = false
        s.pruneRawTracksAfterBackup = false
        let reloaded = CaptureSettings(defaults: d)
        XCTAssertFalse(reloaded.recordCallVideo)
        XCTAssertFalse(reloaded.pruneRawTracksAfterBackup)
    }

    func testBoolHelperTreatsUnsetAsDefault() {
        let d = freshDefaults()
        XCTAssertTrue(CaptureSettings.bool(d, "missing", default: true))
        XCTAssertFalse(CaptureSettings.bool(d, "missing", default: false))
        d.set(false, forKey: "present")
        XCTAssertFalse(CaptureSettings.bool(d, "present", default: true))
    }
}
