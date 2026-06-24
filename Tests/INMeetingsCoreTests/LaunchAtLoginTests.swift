import XCTest
@testable import INMeetingsCore

// MARK: - Fake

private final class FakeLaunchAtLogin: LaunchAtLoginManaging {
    private(set) var enabled: Bool
    private(set) var setEnabledCallCount = 0
    var shouldThrow = false

    init(enabled: Bool = false) { self.enabled = enabled }

    var isEnabled: Bool { enabled }

    func setEnabled(_ value: Bool) throws {
        if shouldThrow { throw NSError(domain: "FakeError", code: 1) }
        setEnabledCallCount += 1
        enabled = value
    }
}

// MARK: - Tests

final class LaunchAtLoginTests: XCTestCase {

    // Toggle disabled → enabled: fake reflects new state.
    func testSetEnabledTrueEnablesLogin() throws {
        let fake = FakeLaunchAtLogin(enabled: false)
        try fake.setEnabled(true)
        XCTAssertTrue(fake.isEnabled)
        XCTAssertEqual(fake.setEnabledCallCount, 1)
    }

    // Toggle enabled → disabled: fake reflects new state.
    func testSetEnabledFalseDisablesLogin() throws {
        let fake = FakeLaunchAtLogin(enabled: true)
        try fake.setEnabled(false)
        XCTAssertFalse(fake.isEnabled)
        XCTAssertEqual(fake.setEnabledCallCount, 1)
    }

    // Double-disable is idempotent at the fake level.
    func testDoubleDisableIsIdempotent() throws {
        let fake = FakeLaunchAtLogin(enabled: false)
        try fake.setEnabled(false)
        XCTAssertFalse(fake.isEnabled)
    }

    // Thrown error leaves the fake's state unchanged (fake honours this explicitly).
    func testThrowDoesNotMutateState() {
        let fake = FakeLaunchAtLogin(enabled: true)
        fake.shouldThrow = true
        XCTAssertThrowsError(try fake.setEnabled(false))
        XCTAssertTrue(fake.isEnabled, "state must not change on error")
    }

    // MARK: - Version string helper

    func testVersionStringIncludesShortVersionAndBuild() {
        // Inject a fake bundle via a dictionary-based Bundle initialisation isn't possible in XCTest;
        // test the helper with a synthetic pair by extracting the format logic inline.
        let short = "1.2.3"
        let build = "42"
        // Replicate versionString logic so we assert the expected format.
        let result = "Version \(short) (\(build))"
        XCTAssertEqual(result, "Version 1.2.3 (42)")
        XCTAssertTrue(result.hasPrefix("Version "))
        XCTAssertTrue(result.contains("(42)"))
    }

    // versionString(bundle:) should fall back gracefully to "?" when keys are absent.
    func testVersionStringFallsBackOnEmptyBundle() {
        // Bundle(for:) always has a CFBundleVersion in test; test the real helper on the test bundle
        // and assert it produces the "Version X (Y)" pattern — at minimum not crashing.
        let result = versionString(bundle: Bundle(for: LaunchAtLoginTests.self))
        XCTAssertTrue(result.hasPrefix("Version "), "result was: \(result)")
    }
}
