import Foundation
import Observation

/// Whether a live call is currently detected, and in which app(s).
public struct DetectionState: Equatable, Sendable {
    public enum Status: Sendable { case idle, armed }
    public var status: Status
    /// Friendly names of the app(s) hosting a detected call (e.g. "Zoom", "Google Chrome (Meet/web call)").
    public var callApps: [String]

    public static let idle = DetectionState(status: .idle, callApps: [])
}

/// Polls Core Audio process I/O and publishes whether a live call is in progress (ADR-001 / P3).
///
/// Observable so the menu bar reacts to `state` changes. Polls every `interval` seconds on the main
/// run loop (the Core Audio reads are cheap). Detection needs no TCC grant.
@available(macOS 14.2, *)
@MainActor
@Observable
public final class CallDetector {
    public private(set) var state: DetectionState = .idle

    private let interval: TimeInterval
    private var timer: Timer?

    /// - Parameters:
    ///   - interval: poll period in seconds.
    ///   - autoStart: begin polling immediately (false in tests).
    public init(interval: TimeInterval = 2.0, autoStart: Bool = true) {
        self.interval = interval
        if autoStart { start() }
    }

    /// Begin polling. Performs an immediate first poll so the menu reflects current state at launch.
    public func start() {
        poll()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop, so we're already on the main actor here.
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let calls = AudioProcessProbe.audioProcesses().filter(\.bidirectional)
        let apps = Set(calls.map(\.app)).sorted()
        state = DetectionState(status: calls.isEmpty ? .idle : .armed, callApps: apps)
    }
}
