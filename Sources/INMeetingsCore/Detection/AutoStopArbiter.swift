import Foundation

/// Decides *when* to offer (and execute) an auto-stop after a recorded call ends — the pure, testable
/// core of the "Meeting ended — stopping in Ns…" feature. Symmetric counterpart to the `idle → armed`
/// start-prompt: it fires on the detector's **`armed → idle`** edge (the call app's audio process exited).
///
/// Deliberately a value type with **no clock, no timers, no UI**: the owner (`MeetingEndCoordinator`)
/// calls ``tick(status:isRecording:enabled:)`` once per second and acts on the returned ``Action``.
/// Counting ticks instead of reading `Date()` keeps every timing path deterministic in tests (the same
/// reason `CallDetector` keeps its logic poll-driven).
///
/// Guarantees: a stop is only ever reached through a visible countdown (`.showCountdown` precedes
/// `.stopNow`); disabling or ending the recording resets cleanly and never stops blind.
public struct AutoStopArbiter: Sendable {
    /// Seconds the call must stay idle after the edge before the countdown card appears (rides out blips).
    public var debounceTicks: Int
    /// Seconds the visible countdown runs before auto-stopping.
    public var countdownTicks: Int

    /// What the owner should do with the card / recorder this tick.
    public enum Action: Equatable, Sendable {
        case none
        /// Show (or refresh) the countdown card with `remaining` seconds.
        case showCountdown(remaining: Int)
        /// Stop + process the recording now (the countdown elapsed).
        case stopNow
        /// Tear down a currently-shown card without stopping (cancelled).
        case hide
    }

    private enum State: Equatable {
        case inactive
        case debouncing(ticksLeft: Int)
        case countingDown(ticksLeft: Int)

        var isShowingCard: Bool {
            if case .countingDown = self { return true }
            return false
        }
    }

    private var state: State = .inactive
    /// The previous tick's armed status — lets us detect the `armed → idle` edge exactly once.
    private var wasArmed = false

    public init(debounceTicks: Int = 12, countdownTicks: Int = 30) {
        self.debounceTicks = debounceTicks
        self.countdownTicks = countdownTicks
    }

    /// Advance one nominal second.
    /// - Parameters:
    ///   - status: the detector's current call status.
    ///   - isRecording: whether a recording is in progress (no recording → nothing to stop).
    ///   - enabled: the user's `autoStopEnabled` setting.
    public mutating func tick(status: DetectionState.Status, isRecording: Bool, enabled: Bool) -> Action {
        let armed = status == .armed
        defer { wasArmed = armed }

        // Auto-stop only applies while actively recording with the feature on. Otherwise reset — and if a
        // card was up, hide it (never stop blind on a setting flip or an external stop).
        guard enabled, isRecording else {
            let wasShowing = state.isShowingCard
            state = .inactive
            return wasShowing ? .hide : .none
        }

        switch state {
        case .inactive:
            // The call just ended (and wasn't already ended) → start the debounce.
            if wasArmed && !armed { state = .debouncing(ticksLeft: debounceTicks) }
            return .none

        case .debouncing(let left):
            if armed {                                  // rejoined within the window → it was a blip
                state = .inactive
                return .none
            }
            let n = left - 1
            if n <= 0 {                                 // sustained idle → reveal the countdown
                state = .countingDown(ticksLeft: countdownTicks)
                return .showCountdown(remaining: countdownTicks)
            }
            state = .debouncing(ticksLeft: n)
            return .none

        case .countingDown(let left):
            if armed {                                  // rejoined while counting down → cancel + hide
                state = .inactive
                return .hide
            }
            let n = left - 1
            if n <= 0 {                                 // countdown elapsed → stop now
                state = .inactive
                return .stopNow
            }
            state = .countingDown(ticksLeft: n)
            return .showCountdown(remaining: n)
        }
    }

    /// User chose "Keep recording": cancel the current offer. A later genuine `armed → idle` edge re-offers.
    public mutating func keepRecording() {
        state = .inactive
    }

    /// The recording was stopped (Stop-now button, menu Stop, quit): reset so we don't act on a stale card.
    public mutating func recordingStopped() {
        state = .inactive
    }
}
