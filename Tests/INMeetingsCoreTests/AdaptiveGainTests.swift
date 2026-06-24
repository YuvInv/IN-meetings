import XCTest
@testable import INMeetingsCore

final class AdaptiveGainTests: XCTestCase {
    /// A quiet sine fed through enough blocks should be lifted toward the target level.
    func testQuietSignalIsRaisedTowardTarget() {
        var gain = AdaptiveGain(targetDBFS: -18)
        let quiet = Self.sine(dBFS: -40, frames: 4096)
        var lastRMS: Float = 0
        // Feed several blocks so the attack smoothing converges.
        for _ in 0..<200 {
            var block = quiet
            gain.apply(to: &block)
            lastRMS = Self.rms(block)
        }
        let resultDB = 20 * log10(lastRMS)
        // Should land near the −18 dBFS target (within a few dB once converged), and clearly louder
        // than the −40 dBFS input.
        XCTAssertGreaterThan(resultDB, -22)
        XCTAssertLessThan(resultDB, -14)
    }

    /// A hot signal must never push samples past the soft-clip ceiling (no hard clipping).
    func testHotSignalNeverExceedsCeiling() {
        var gain = AdaptiveGain(targetDBFS: -18)
        for _ in 0..<200 {
            var block = Self.sine(dBFS: 0, frames: 4096, amplitude: 1.5) // deliberately over full-scale
            gain.apply(to: &block)
            for sample in block {
                XCTAssertLessThanOrEqual(abs(sample), 0.999 + 1e-4)
            }
        }
    }

    func testEmptyBufferIsNoOp() {
        var gain = AdaptiveGain(targetDBFS: -18)
        var empty: [Float] = []
        gain.apply(to: &empty)   // must not crash
        XCTAssertTrue(empty.isEmpty)
    }

    func testSilenceStaysSilent() {
        var gain = AdaptiveGain(targetDBFS: -18)
        var silence = [Float](repeating: 0, count: 1024)
        gain.apply(to: &silence)
        for sample in silence { XCTAssertEqual(sample, 0, accuracy: 1e-6) }
    }

    // MARK: - Helpers

    /// A mono sine block at the requested RMS level (dBFS). `amplitude` overrides the peak directly
    /// when set (for over-scale stress tests).
    private static func sine(dBFS: Float, frames: Int, amplitude overrideAmplitude: Float? = nil) -> [Float] {
        // For a sine, RMS = amplitude / sqrt(2) → amplitude = 10^(dBFS/20) * sqrt(2).
        let amplitude = overrideAmplitude ?? (pow(10, dBFS / 20) * Float(2).squareRoot())
        return (0..<frames).map { i in
            amplitude * sin(2 * .pi * 440 * Float(i) / 48_000)
        }
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumSquares / Float(samples.count)).squareRoot()
    }
}
