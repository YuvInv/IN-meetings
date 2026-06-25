import AVFoundation
import XCTest
@testable import INMeetingsCore

final class LevelMeterTests: XCTestCase {
    /// `dBFS` must match MicRecorder's original formula (`peak > 0 ? 20*log10(peak) : -120`).
    func testDBFSMatchesLegacyFormula() {
        XCTAssertEqual(LevelMeter.dBFS(1.0), 0, accuracy: 1e-5)        // full-scale → 0 dBFS
        XCTAssertEqual(LevelMeter.dBFS(0.5), -6.0206, accuracy: 1e-3) // half → ~−6 dB
        XCTAssertEqual(LevelMeter.dBFS(0), -120)                      // pure silence → floor
        XCTAssertEqual(LevelMeter.dBFS(-0.0), -120)                   // signed-zero is still silence
    }

    func testPeakOverSyntheticBuffer() {
        var meter = LevelMeter()
        let buffer = Self.buffer(samples: [0.1, -0.7, 0.3, -0.2])
        let result = meter.process(buffer)
        XCTAssertEqual(result.peak, 0.7, accuracy: 1e-6)   // largest |sample|
    }

    func testRMSOverSyntheticBuffer() {
        var meter = LevelMeter()
        // RMS of [0.5, -0.5, 0.5, -0.5] = 0.5.
        let result = meter.process(Self.buffer(samples: [0.5, -0.5, 0.5, -0.5]))
        XCTAssertEqual(result.rms, 0.5, accuracy: 1e-6)
    }

    func testEmptyBufferIsSilent() {
        var meter = LevelMeter()
        let result = meter.process(Self.buffer(samples: []))
        XCTAssertEqual(result.peak, 0)
        XCTAssertEqual(result.rms, 0)
    }

    /// A mono float buffer from raw samples, for deterministic metering tests.
    private static func buffer(samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData {
            for (i, value) in samples.enumerated() { channel[0][i] = value }
        }
        return buffer
    }
}
