import XCTest
@testable import INMeetingsCore

/// The auto-stop state machine is pure and tick-driven (no clock, no UI), so every timing path is
/// deterministic here: each `tick` is one nominal second. Short debounce/countdown windows keep the
/// tests terse. Mirrors how `DetectionTests` exercises the detector's pure logic without live audio.
final class AutoStopArbiterTests: XCTestCase {
    /// debounce 2, countdown 3 → easy to reason about by hand.
    private func makeArbiter() -> AutoStopArbiter {
        AutoStopArbiter(debounceTicks: 2, countdownTicks: 3)
    }

    /// Drive an armed→idle edge: one armed tick (seeds `wasArmed`), then idle ticks.
    private func arm(_ a: inout AutoStopArbiter) {
        _ = a.tick(status: .armed, isRecording: true, enabled: true)
    }

    func testHappyPath_debounceThenCountdownThenStop() {
        var a = makeArbiter()
        arm(&a)
        // First idle tick = the armed→idle edge → enters debounce, no card yet.
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .none)
        // Debounce 2 ticks then the card appears at the full countdown.
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .none)
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .showCountdown(remaining: 3))
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .showCountdown(remaining: 2))
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .showCountdown(remaining: 1))
        // Countdown hits zero → stop exactly once.
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .stopNow)
        // Then quiescent (no repeated stops).
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .none)
    }

    func testReArmDuringDebounceCancels() {
        var a = makeArbiter()
        arm(&a)
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .none)   // edge → debounce
        // Re-arms before the debounce elapses → blip, cancel. No card ever shows.
        XCTAssertEqual(a.tick(status: .armed, isRecording: true, enabled: true), .none)
        // Stays idle again but this is the SAME idle stretch — only a fresh armed→idle re-arms.
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .none)    // new edge → debounce
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .none)
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .showCountdown(remaining: 3))
    }

    func testReArmDuringCountdownCancelsAndHides() {
        var a = makeArbiter()
        arm(&a)
        a.run(idleTicks: 3)   // through debounce into the countdown
        // Re-arm while counting down → hide the card, keep recording.
        XCTAssertEqual(a.tick(status: .armed, isRecording: true, enabled: true), .hide)
        XCTAssertEqual(a.tick(status: .armed, isRecording: true, enabled: true), .none)
    }

    func testKeepRecordingCancels_thenFreshEdgeReoffers() {
        var a = makeArbiter()
        arm(&a)
        a.run(idleTicks: 3)   // card up
        a.keepRecording()     // user cancels
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .none)   // stays cancelled while idle
        // A genuine new call-end (armed then idle) re-offers.
        XCTAssertEqual(a.tick(status: .armed, isRecording: true, enabled: true), .none)
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .none)   // new edge → debounce
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .none)
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .showCountdown(remaining: 3))
    }

    func testDisabledNeverFires() {
        var a = makeArbiter()
        _ = a.tick(status: .armed, isRecording: true, enabled: false)
        for _ in 0..<10 {
            XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: false), .none)
        }
    }

    func testNotRecordingNeverFires() {
        var a = makeArbiter()
        _ = a.tick(status: .armed, isRecording: false, enabled: true)
        for _ in 0..<10 {
            XCTAssertEqual(a.tick(status: .idle, isRecording: false, enabled: true), .none)
        }
    }

    func testDisablingMidCountdownHidesTheCard() {
        var a = makeArbiter()
        arm(&a)
        a.run(idleTicks: 3)   // card up
        // The user flips the Settings toggle off mid-countdown → hide, never stop blind.
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: false), .hide)
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: false), .none)
    }

    func testRecordingStoppedMidFlowResets() {
        var a = makeArbiter()
        arm(&a)
        a.run(idleTicks: 3)        // card up
        a.recordingStopped()       // e.g. user hit Stop now / menu Stop
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .none)
    }

    func testCallAlreadyActiveAtLaunchThenEndsFires() {
        // App opened mid-call: first observed status is armed while not yet recording.
        var a = makeArbiter()
        _ = a.tick(status: .armed, isRecording: false, enabled: true)
        // Recording starts (still armed) — no edge.
        XCTAssertEqual(a.tick(status: .armed, isRecording: true, enabled: true), .none)
        // Call ends → edge → debounce → countdown.
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .none)
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .none)
        XCTAssertEqual(a.tick(status: .idle, isRecording: true, enabled: true), .showCountdown(remaining: 3))
    }
}

private extension AutoStopArbiter {
    /// Feed N idle, recording, enabled ticks (test convenience).
    mutating func run(idleTicks n: Int) {
        for _ in 0..<n { _ = tick(status: .idle, isRecording: true, enabled: true) }
    }
}
