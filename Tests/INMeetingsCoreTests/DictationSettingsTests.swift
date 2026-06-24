import Carbon
import XCTest
@testable import INMeetingsCore

@MainActor
final class DictationSettingsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "dict-\(UUID().uuidString)")! }

    func testDefaultsAreOffAndHebrewWithExpectedChords() {
        let s = DictationSettings(defaults: freshDefaults())
        XCTAssertFalse(s.enabled)                 // opt-in: default OFF
        XCTAssertEqual(s.defaultLanguage, "he")   // Hebrew by default
        // ⌃⌥⌘D (Hebrew) and ⌃⌥⌘E (English).
        XCTAssertEqual(s.heKeyCode, UInt32(kVK_ANSI_D))
        XCTAssertEqual(s.enKeyCode, UInt32(kVK_ANSI_E))
        let mods = UInt32(controlKey | optionKey | cmdKey)
        XCTAssertEqual(s.heModifiers, mods)
        XCTAssertEqual(s.enModifiers, mods)
    }

    func testChangesPersistAcrossReload() {
        let d = freshDefaults()
        let s = DictationSettings(defaults: d)
        s.enabled = true
        s.defaultLanguage = "en"
        s.heKeyCode = UInt32(kVK_ANSI_K)
        s.heModifiers = UInt32(cmdKey)
        s.enKeyCode = UInt32(kVK_ANSI_L)
        s.enModifiers = UInt32(controlKey)

        let reloaded = DictationSettings(defaults: d)
        XCTAssertTrue(reloaded.enabled)
        XCTAssertEqual(reloaded.defaultLanguage, "en")
        XCTAssertEqual(reloaded.heKeyCode, UInt32(kVK_ANSI_K))
        XCTAssertEqual(reloaded.heModifiers, UInt32(cmdKey))
        XCTAssertEqual(reloaded.enKeyCode, UInt32(kVK_ANSI_L))
        XCTAssertEqual(reloaded.enModifiers, UInt32(controlKey))
    }

    func testUint32HelperTreatsUnsetAsDefault() {
        let d = freshDefaults()
        XCTAssertEqual(DictationSettings.uint32(d, "missing", default: 42), 42)
        d.set(7, forKey: "present")
        XCTAssertEqual(DictationSettings.uint32(d, "present", default: 42), 7)
    }
}
