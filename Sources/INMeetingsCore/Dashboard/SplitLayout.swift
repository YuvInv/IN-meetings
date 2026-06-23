import Foundation

/// Pure geometry for a two-pane draggable splitter — no SwiftUI, so it is unit-testable.
/// `fraction` is the FIRST pane's share of the usable length (`total` minus the divider thickness),
/// in 0...1.
public enum SplitLayout {
    /// Clamp a requested divider `fraction` to a legal value: each pane keeps at least its minimum
    /// length. If the container is too small to honor both minimums, the panes split the usable length
    /// proportionally to their minimums. Never returns NaN or a value outside 0...1 (minimums are
    /// assumed non-negative; negative minimums are clamped so the result still stays in 0...1).
    public static func clampFraction(_ fraction: Double, total: Double, min0: Double, min1: Double,
                                     divider: Double = 0) -> Double {
        let usable = total - divider
        guard usable > 0 else { return 0.5 }
        if min0 + min1 >= usable {
            let denom = min0 + min1
            return denom > 0 ? min0 / denom : 0.5
        }
        let lo = Swift.max(0, min0 / usable)
        let hi = Swift.min(1, 1 - (min1 / usable))
        let f = fraction.isFinite ? fraction : 0.5
        return Swift.min(Swift.max(f, lo), hi)
    }

    /// The first pane's length in points for `fraction` of the usable length (`total` minus `divider`).
    public static func firstLength(fraction: Double, total: Double, divider: Double = 0) -> Double {
        Swift.max(0, (total - divider) * fraction)
    }
}
