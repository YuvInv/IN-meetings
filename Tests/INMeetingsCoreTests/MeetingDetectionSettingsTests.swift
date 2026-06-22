import XCTest
@testable import INMeetingsCore

@available(macOS 14.2, *)
@MainActor
final class MeetingDetectionSettingsTests: XCTestCase {
    /// Fresh, isolated defaults suite per test (don't pollute `.standard`).
    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "MeetingDetectionSettingsTests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testEnabledByDefault() {
        let s = MeetingDetectionSettings(defaults: makeDefaults("default"))
        XCTAssertTrue(s.promptEnabled)
        XCTAssertFalse(s.isSnoozed)
    }

    func testSnoozeThenResume() {
        let s = MeetingDetectionSettings(defaults: makeDefaults("snooze"))
        XCTAssertFalse(s.isSnoozed)
        s.snooze()
        XCTAssertTrue(s.isSnoozed)
        XCTAssertNotNil(s.snoozeUntil)
        s.resume()
        XCTAssertFalse(s.isSnoozed)
        XCTAssertNil(s.snoozeUntil)
    }

    func testDisablePersistsAcrossInstances() {
        let d = makeDefaults("disable")
        let s1 = MeetingDetectionSettings(defaults: d)
        XCTAssertFalse(s1.isDisabled(app: "Zoom"))
        s1.disable(app: "Zoom")
        XCTAssertTrue(s1.isDisabled(app: "Zoom"))
        // A fresh instance over the same suite must see the persisted silence.
        let s2 = MeetingDetectionSettings(defaults: d)
        XCTAssertTrue(s2.isDisabled(app: "Zoom"))
        s2.enable(app: "Zoom")
        XCTAssertFalse(s2.isDisabled(app: "Zoom"))
    }

    func testPromptEnabledPersists() {
        let d = makeDefaults("enabledPersist")
        let s1 = MeetingDetectionSettings(defaults: d)
        s1.promptEnabled = false
        let s2 = MeetingDetectionSettings(defaults: d)
        XCTAssertFalse(s2.promptEnabled)
    }

    func testAutoStopEnabledByDefaultAndPersists() {
        let d = makeDefaults("autoStop")
        let s1 = MeetingDetectionSettings(defaults: d)
        XCTAssertTrue(s1.autoStopEnabled)   // ON by default, discoverable
        s1.autoStopEnabled = false
        let s2 = MeetingDetectionSettings(defaults: d)
        XCTAssertFalse(s2.autoStopEnabled)  // persisted across instances
    }
}
