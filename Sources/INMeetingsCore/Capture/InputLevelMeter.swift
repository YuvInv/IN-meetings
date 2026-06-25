import AVFoundation
import Foundation

/// Meters a stream of `AVAudioPCMBuffer`s, tracking the running **peak** (largest absolute sample) and the
/// per-buffer RMS. Extracted from `MicRecorder` so the same dB math drives the recorder's self-check, the
/// live Settings VU meter, and adaptive-gain decisions — and so it can be unit-tested without hardware.
struct LevelMeter {
    /// Largest absolute sample seen since the meter was created (carried across buffers, like MicRecorder).
    private(set) var peak: Float = 0

    /// Updates the running peak from `buffer` and returns that buffer's `(rms, peak)`. The returned `peak`
    /// is the running peak (matching MicRecorder's whole-capture peak); `rms` is for this buffer only.
    mutating func process(_ buffer: AVAudioPCMBuffer) -> (rms: Float, peak: Float) {
        guard let channels = buffer.floatChannelData else { return (0, peak) }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return (0, peak) }

        var sumSquares: Float = 0
        for c in 0..<channelCount {
            let samples = channels[c]
            for i in 0..<frames {
                let v = abs(samples[i])
                if v > peak { peak = v }
                sumSquares += samples[i] * samples[i]
            }
        }
        let rms = (sumSquares / Float(frames * channelCount)).squareRoot()
        return (rms, peak)
    }

    /// Linear amplitude (0…1) as dBFS, matching MicRecorder's original `peak > 0 ? 20*log10 : −120` —
    /// a silence floor of −120 dB instead of `-inf`.
    static func dBFS(_ linear: Float) -> Float {
        linear > 0 ? 20 * log10(linear) : -120
    }
}
