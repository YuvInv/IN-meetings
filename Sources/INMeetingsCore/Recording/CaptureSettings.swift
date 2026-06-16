import Foundation
import Observation

/// User preferences for what a recording captures and how long raw files are kept (V1 video slice).
///
/// Persisted in `UserDefaults`, all ON by default:
///  - `recordCallVideo` — film the call window (ScreenCaptureKit, window-only HEVC) alongside the audio
///    tracks for `call` recordings. Off → audio-only (and no Screen-Recording prompt). In-person is
///    always audio-only regardless.
///  - `pruneRawTracksAfterBackup` — once a meeting's merged playback file (`meeting.mp4` / `audio.m4a`)
///    is safely on Drive, delete the local raw `mic.wav` / `system.wav` / `video.mov` to reclaim disk
///    (video makes recordings GB-scale). The merged file + the package stay; the raw tracks live on Drive.
///  - `autoSummary` — when a `call` finishes, automatically run the bundled `saventa-summary` recipe via
///    headless `claude -p` to write `summary.md` (the dashboard shows it; Drive syncs it). Off → only the
///    per-meeting **Summarize** button makes one. File-only (no external action), so safe to default on.
///
/// The keys are also read directly from `UserDefaults` by `DriveSync` (off the main actor), so they're
/// exposed as `Keys` rather than gated behind this `@MainActor` model.
@MainActor
@Observable
public final class CaptureSettings {
    public var recordCallVideo: Bool {
        didSet { defaults.set(recordCallVideo, forKey: Keys.recordCallVideo) }
    }
    public var pruneRawTracksAfterBackup: Bool {
        didSet { defaults.set(pruneRawTracksAfterBackup, forKey: Keys.pruneRawTracksAfterBackup) }
    }
    public var autoSummary: Bool {
        didSet { defaults.set(autoSummary, forKey: Keys.autoSummary) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recordCallVideo = Self.bool(defaults, Keys.recordCallVideo, default: true)
        self.pruneRawTracksAfterBackup = Self.bool(defaults, Keys.pruneRawTracksAfterBackup, default: true)
        self.autoSummary = Self.bool(defaults, Keys.autoSummary, default: true)
    }

    public enum Keys {
        public static let recordCallVideo = "capture.recordCallVideo"
        public static let pruneRawTracksAfterBackup = "capture.pruneRawTracksAfterBackup"
        public static let autoSummary = "capture.autoSummary"
    }

    /// A `Bool` default that treats "never set" as `default` (UserDefaults.bool returns false when absent).
    /// `nonisolated` so `DriveSync` can read the retention flag off the main actor.
    public nonisolated static func bool(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}
