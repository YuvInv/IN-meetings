// Adapted from Mila (https://github.com/island-io/mila), © Island Technology, Inc. / Uri Harduf,
// Apache-2.0. Changes: rewritten for IN-meetings' @Observable/@MainActor model (Mila used Combine
// ObservableObject); keyed on the detector's friendly app name (we have no bundle ID in DetectionState);
// global snooze instead of per-bundle. See THIRD_PARTY_NOTICES.md.

import Foundation
import Observation

/// User preferences for the "Record now" call-prompt overlay (Harvest 3).
///
/// Persisted in `UserDefaults`:
///  - `promptEnabled` — master on/off (ON by default so the feature is discoverable).
///  - `autoStopEnabled` — symmetric "offer to stop when the call ends" countdown (ON by default).
///  - `snoozeUntil` — after a "Not now", suppress *all* prompts until this time (1 h window).
///  - `disabledApps` — friendly app names the user permanently silenced (e.g. "Zoom").
///
/// We key silencing on the detector's friendly app name (`DetectionState.callApps`) because the
/// Core Audio probe gives us names, not bundle IDs.
@available(macOS 14.2, *)
@MainActor
@Observable
public final class MeetingDetectionSettings {
    /// How long a "Not now" suppresses prompts. Matches Mila's 60-minute floor.
    public static let snoozeDuration: TimeInterval = 60 * 60

    public var promptEnabled: Bool {
        didSet { defaults.set(promptEnabled, forKey: Keys.enabled) }
    }
    /// Whether to float the "Meeting ended — stopping in Ns…" countdown when a recorded call ends.
    public var autoStopEnabled: Bool {
        didSet { defaults.set(autoStopEnabled, forKey: Keys.autoStop) }
    }
    public private(set) var snoozeUntil: Date? {
        didSet { defaults.set(snoozeUntil?.timeIntervalSince1970 ?? 0, forKey: Keys.snooze) }
    }
    public private(set) var disabledApps: Set<String> {
        didSet { defaults.set(Array(disabledApps), forKey: Keys.disabled) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // ON by default on first launch so users discover the feature.
        if defaults.object(forKey: Keys.enabled) == nil {
            defaults.set(true, forKey: Keys.enabled)
        }
        if defaults.object(forKey: Keys.autoStop) == nil {
            defaults.set(true, forKey: Keys.autoStop)
        }
        self.promptEnabled = defaults.bool(forKey: Keys.enabled)
        self.autoStopEnabled = defaults.bool(forKey: Keys.autoStop)
        let ts = defaults.double(forKey: Keys.snooze)
        self.snoozeUntil = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        self.disabledApps = Set(defaults.stringArray(forKey: Keys.disabled) ?? [])
    }

    /// True iff a recent "Not now" should still suppress prompts.
    public var isSnoozed: Bool {
        guard let snoozeUntil else { return false }
        return snoozeUntil > Date()
    }

    public func isDisabled(app: String) -> Bool { disabledApps.contains(app) }

    /// Suppress all prompts for `snoozeDuration` (called on "Not now").
    public func snooze() {
        snoozeUntil = Date().addingTimeInterval(Self.snoozeDuration)
    }

    /// Clear a snooze (menu "Resume call prompts").
    public func resume() { snoozeUntil = nil }

    /// Permanently silence prompts for one app ("Don't ask for <app>").
    public func disable(app: String) {
        guard !app.isEmpty else { return }
        disabledApps.insert(app)
    }

    /// Undo a silence (re-enable a previously silenced app).
    public func enable(app: String) { disabledApps.remove(app) }

    private enum Keys {
        static let enabled = "meetingPrompt.enabled"
        static let autoStop = "meetingPrompt.autoStopEnabled"
        static let snooze = "meetingPrompt.snoozeUntil"
        static let disabled = "meetingPrompt.disabledApps"
    }
}
