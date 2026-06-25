import XCTest
@testable import INMeetingsCore

@MainActor
final class AudioDeviceSettingsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "audio-\(UUID().uuidString)")! }

    func testDefaultsOnFirstLaunch() {
        let s = AudioDeviceSettings(defaults: freshDefaults())
        XCTAssertNil(s.selectedInputDeviceUID)        // system default until the user picks
        XCTAssertFalse(s.adaptiveGainEnabled)         // opt-in: don't alter the source-of-truth mic silently
        XCTAssertEqual(s.targetInputLevelDBFS, -18, accuracy: 1e-6)
    }

    func testChangesPersistAcrossReload() {
        let d = freshDefaults()
        let s = AudioDeviceSettings(defaults: d)
        s.selectedInputDeviceUID = "iface-uid"
        s.adaptiveGainEnabled = true
        s.targetInputLevelDBFS = -12
        let reloaded = AudioDeviceSettings(defaults: d)
        XCTAssertEqual(reloaded.selectedInputDeviceUID, "iface-uid")
        XCTAssertTrue(reloaded.adaptiveGainEnabled)
        XCTAssertEqual(reloaded.targetInputLevelDBFS, -12, accuracy: 1e-6)
    }

    func testClearingSelectionPersistsAsNil() {
        let d = freshDefaults()
        let s = AudioDeviceSettings(defaults: d)
        s.selectedInputDeviceUID = "iface-uid"
        s.selectedInputDeviceUID = nil
        let reloaded = AudioDeviceSettings(defaults: d)
        XCTAssertNil(reloaded.selectedInputDeviceUID)
    }

    func testResolvedDeviceUIDReturnsSelectedWhenPresent() {
        let s = AudioDeviceSettings(defaults: freshDefaults())
        s.selectedInputDeviceUID = "iface-uid"
        let available = [
            AudioInputDevice(uid: "mic-uid", name: "Built-in Mic", id: 10),
            AudioInputDevice(uid: "iface-uid", name: "USB Interface", id: 20),
        ]
        XCTAssertEqual(s.resolvedDeviceUID(available: available), "iface-uid")
    }

    func testResolvedDeviceUIDFallsBackWhenUnplugged() {
        let s = AudioDeviceSettings(defaults: freshDefaults())
        s.selectedInputDeviceUID = "unplugged-uid"
        let available = [AudioInputDevice(uid: "mic-uid", name: "Built-in Mic", id: 10)]
        XCTAssertNil(s.resolvedDeviceUID(available: available))   // degrade to system default
    }

    func testResolvedDeviceUIDIsNilWhenNoSelection() {
        let s = AudioDeviceSettings(defaults: freshDefaults())
        let available = [AudioInputDevice(uid: "mic-uid", name: "Built-in Mic", id: 10)]
        XCTAssertNil(s.resolvedDeviceUID(available: available))
    }

    func testStringAndDoubleHelpersTreatUnsetAsDefault() {
        let d = freshDefaults()
        XCTAssertNil(AudioDeviceSettings.string(d, "missing", default: nil))
        XCTAssertEqual(AudioDeviceSettings.string(d, "missing", default: "fallback"), "fallback")
        XCTAssertEqual(AudioDeviceSettings.double(d, "missing", default: -18), -18, accuracy: 1e-6)
        d.set(-9.0, forKey: "present")
        XCTAssertEqual(AudioDeviceSettings.double(d, "present", default: -18), -9, accuracy: 1e-6)
    }
}
