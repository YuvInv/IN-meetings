import Foundation
import Observation

/// User preferences for the microphone input: which device to record from, and optional adaptive gain.
///
/// Persisted in `UserDefaults`, mirroring `CaptureSettings`:
///  - `selectedInputDeviceUID` — the chosen device's persistent UID, or nil for **System Default**. A UID
///    (not the numeric `AudioDeviceID`, which is unstable across reboots/re-plugs) so a saved choice
///    survives; an unplugged device degrades gracefully via `resolvedDeviceUID(available:)`.
///  - `adaptiveGainEnabled` — auto-boost a quiet mic toward `targetInputLevelDBFS`. **Off by default**: the
///    raw mic is the source of truth for transcription of confidential meetings, so we don't alter it
///    silently (opt-in).
///  - `targetInputLevelDBFS` — the loudness adaptive gain steers toward (default −18 dBFS).
@MainActor
@Observable
public final class AudioDeviceSettings {
    public var selectedInputDeviceUID: String? {
        didSet { defaults.set(selectedInputDeviceUID, forKey: Keys.inputDeviceUID) }
    }
    public var adaptiveGainEnabled: Bool {
        didSet { defaults.set(adaptiveGainEnabled, forKey: Keys.adaptiveGain) }
    }
    public var targetInputLevelDBFS: Double {
        didSet { defaults.set(targetInputLevelDBFS, forKey: Keys.targetDBFS) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedInputDeviceUID = Self.string(defaults, Keys.inputDeviceUID, default: nil)
        self.adaptiveGainEnabled = Self.bool(defaults, Keys.adaptiveGain, default: false)
        self.targetInputLevelDBFS = Self.double(defaults, Keys.targetDBFS, default: -18)
    }

    /// The UID to actually record from, given what's currently plugged in: the saved selection iff it's in
    /// `available`, else nil (System Default). So an unplugged selected device degrades gracefully instead
    /// of failing to record (decision 4).
    public func resolvedDeviceUID(available: [AudioInputDevice]) -> String? {
        guard let selectedInputDeviceUID,
              available.contains(where: { $0.uid == selectedInputDeviceUID }) else { return nil }
        return selectedInputDeviceUID
    }

    public enum Keys {
        public static let inputDeviceUID = "audio.inputDeviceUID"
        public static let adaptiveGain = "audio.adaptiveGain"
        public static let targetDBFS = "audio.targetDBFS"
    }

    /// A `Bool` default that treats "never set" as `default` (UserDefaults.bool returns false when absent).
    public nonisolated static func bool(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    /// A `String?` default that treats "never set" as `default`.
    public nonisolated static func string(_ defaults: UserDefaults, _ key: String, default fallback: String?) -> String? {
        defaults.object(forKey: key) as? String ?? fallback
    }

    /// A `Double` default that treats "never set" as `default` (UserDefaults.double returns 0 when absent).
    public nonisolated static func double(_ defaults: UserDefaults, _ key: String, default fallback: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? fallback
    }
}
