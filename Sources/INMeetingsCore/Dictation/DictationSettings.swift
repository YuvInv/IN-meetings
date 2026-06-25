import Carbon
import Foundation
import Observation

/// User preferences for the global-hotkey dictation feature (A6) — **opt-in, default OFF**.
///
/// Persisted in `UserDefaults`, mirroring `CaptureSettings`/`AudioDeviceSettings`:
///  - `enabled` — master switch. **Off by default**: dictation registers two extra global hotkeys and
///    needs the Accessibility grant to paste, so it stays dormant until the user turns it on
///    (`DictationController` only registers the chords while this is true).
///  - `defaultLanguage` — ASR language for the menu hint / overlay copy (the two chords pick the actual
///    language; this is just the labelled default). Default Hebrew (`"he"`).
///  - the two chords (`heKeyCode/heModifiers` + `enKeyCode/enModifiers`, all `UInt32` for
///    `GlobalHotKey`): Hebrew defaults to ⌃⌥⌘D, English to ⌃⌥⌘E. The rebinding UI is deferred —
///    `GlobalHotKey` already supports arbitrary chords, so these persist for when it lands.
@MainActor
@Observable
public final class DictationSettings {
    public var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Keys.enabled) }
    }
    public var defaultLanguage: String {
        didSet { defaults.set(defaultLanguage, forKey: Keys.defaultLanguage) }
    }
    public var heKeyCode: UInt32 {
        didSet { defaults.set(Int(heKeyCode), forKey: Keys.heKeyCode) }
    }
    public var heModifiers: UInt32 {
        didSet { defaults.set(Int(heModifiers), forKey: Keys.heModifiers) }
    }
    public var enKeyCode: UInt32 {
        didSet { defaults.set(Int(enKeyCode), forKey: Keys.enKeyCode) }
    }
    public var enModifiers: UInt32 {
        didSet { defaults.set(Int(enModifiers), forKey: Keys.enModifiers) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabled = Self.bool(defaults, Keys.enabled, default: false)
        self.defaultLanguage = Self.string(defaults, Keys.defaultLanguage, default: "he")
        self.heKeyCode = Self.uint32(defaults, Keys.heKeyCode, default: Self.defaultHeKeyCode)
        self.heModifiers = Self.uint32(defaults, Keys.heModifiers, default: Self.defaultModifiers)
        self.enKeyCode = Self.uint32(defaults, Keys.enKeyCode, default: Self.defaultEnKeyCode)
        self.enModifiers = Self.uint32(defaults, Keys.enModifiers, default: Self.defaultModifiers)
    }

    // MARK: - Default chords

    /// ⌃⌥⌘ — shared by both dictation chords (only the letter differs), matching `GlobalHotKey`'s record
    /// chord family.
    public static let defaultModifiers = UInt32(controlKey | optionKey | cmdKey)
    /// "D" (Dictate, Hebrew).
    public static let defaultHeKeyCode = UInt32(kVK_ANSI_D)
    /// "E" (English).
    public static let defaultEnKeyCode = UInt32(kVK_ANSI_E)

    public enum Keys {
        public static let enabled = "dictation.enabled"
        public static let defaultLanguage = "dictation.defaultLanguage"
        public static let heKeyCode = "dictation.heKeyCode"
        public static let heModifiers = "dictation.heModifiers"
        public static let enKeyCode = "dictation.enKeyCode"
        public static let enModifiers = "dictation.enModifiers"
    }

    /// A `Bool` default that treats "never set" as `default` (UserDefaults.bool returns false when absent).
    public nonisolated static func bool(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    /// A `String` default that treats "never set" as `default`.
    public nonisolated static func string(_ defaults: UserDefaults, _ key: String, default fallback: String) -> String {
        defaults.object(forKey: key) as? String ?? fallback
    }

    /// A `UInt32` default that treats "never set" as `default` (stored as `Int` in UserDefaults).
    public nonisolated static func uint32(_ defaults: UserDefaults, _ key: String, default fallback: UInt32) -> UInt32 {
        guard let n = defaults.object(forKey: key) as? Int, n >= 0 else { return fallback }
        return UInt32(n)
    }
}
