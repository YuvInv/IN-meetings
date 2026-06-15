import XCTest
@testable import INMeetingsCore

/// Covers the pure bundle-ID normalization used to name detected calls. The Core Audio probe itself
/// is exercised live (prototype P3 + the slice-2 manual test) since it depends on real system audio.
final class DetectionTests: XCTestCase {
    func testHelperSuffixIsStrippedThenFriendlyNamed() {
        XCTAssertEqual(
            AudioProcessProbe.normalizedApp("com.google.Chrome.helper (Renderer)"),
            "Google Chrome (Meet/web call)")
    }

    func testKnownBundleGetsFriendlyName() {
        XCTAssertEqual(AudioProcessProbe.normalizedApp("us.zoom.xos"), "Zoom")
    }

    func testUnknownBundlePassesThrough() {
        XCTAssertEqual(AudioProcessProbe.normalizedApp("com.acme.whatever"), "com.acme.whatever")
    }

    /// The bundle id ScreenCaptureKit matches windows on: helper suffix stripped, but NOT friendly-named
    /// (SCRunningApplication.bundleIdentifier is the real id, e.g. "com.google.Chrome").
    func testStrippedBundleIDDropsHelperSuffixButKeepsTheRealID() {
        XCTAssertEqual(AudioProcessProbe.strippedBundleID("com.google.Chrome.helper (Renderer)"),
                       "com.google.Chrome")
        XCTAssertEqual(AudioProcessProbe.strippedBundleID("us.zoom.xos"), "us.zoom.xos")
    }
}
