import Foundation
import Observation

/// User preference for the active summary recipe. Persisted in `UserDefaults`.
///
/// Like `CaptureSettings`, the key is also read **off the main actor** (from `JobBridge` on a
/// background thread), so it's exposed as a `nonisolated static` helper rather than a computed
/// property of this `@MainActor @Observable` model.
@MainActor
@Observable
public final class SummaryRecipeSettings {
    /// The id of the currently selected recipe (folder name), e.g. `"saventa-summary"`.
    public var activeRecipeID: String {
        didSet { defaults.set(activeRecipeID, forKey: Keys.activeRecipe) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.activeRecipeID = Self.activeRecipeID(defaults)
    }

    public enum Keys {
        public static let activeRecipe = "summary.activeRecipe"
    }

    /// Off-main-actor read of `activeRecipeID` from any `UserDefaults` suite.
    /// `nonisolated` so `JobBridge` (and other `@Sendable` callers) can read it without a main-actor hop.
    public nonisolated static func activeRecipeID(_ defaults: UserDefaults) -> String {
        string(defaults, Keys.activeRecipe, default: "saventa-summary")
    }

    /// Generic `String` default that treats "never set" as `default`
    /// (`UserDefaults.string` returns `nil` when absent).
    public nonisolated static func string(
        _ defaults: UserDefaults,
        _ key: String,
        default fallback: String
    ) -> String {
        defaults.string(forKey: key) ?? fallback
    }
}
