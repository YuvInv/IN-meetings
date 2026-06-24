import Foundation

/// Auto-levels a quiet microphone toward a target loudness, with attack/release smoothing and a tanh
/// soft-clip so a sudden-loud signal rounds over the ceiling instead of hard-clipping. Pure DSP over
/// `[Float]` (no AVFoundation), so it is fully unit-testable.
///
/// Opt-in by design (see DECISIONS / the A1 brief): the raw mic is the source of truth for transcription
/// of confidential meetings, so we never alter it silently — `AdaptiveGain` is only built when the user
/// turns on "Adaptive gain". The gain itself is bounded (`maxGain`) so we boost a genuinely quiet mic but
/// never amplify a silent track into noise.
public struct AdaptiveGain {
    /// Loudness we steer the signal toward, in dBFS (RMS). Default −18 dBFS (the brief's target).
    public let targetDBFS: Float
    /// Hard cap on the linear boost, so room tone / silence isn't amplified into hiss (+24 dB ≈ 16×).
    public let maxGain: Float
    /// Per-buffer smoothing factors (0…1). A small attack means gain ramps up gradually toward a louder
    /// target; release lets it ease back down. Asymmetric (slower up than down) to avoid pumping.
    public let attack: Float
    public let release: Float
    /// Don't try to lift signals quieter than this — they're effectively silence (room tone), and boosting
    /// them just raises the noise floor.
    public let noiseFloorDBFS: Float

    /// The currently-applied linear gain, smoothed across buffers. Starts at unity.
    private var currentGain: Float = 1

    public init(targetDBFS: Float = -18,
                maxGain: Float = 16,        // +24 dB
                attack: Float = 0.05,
                release: Float = 0.2,
                noiseFloorDBFS: Float = -60) {
        self.targetDBFS = targetDBFS
        self.maxGain = maxGain
        self.attack = attack
        self.release = release
        self.noiseFloorDBFS = noiseFloorDBFS
    }

    /// Smooths the gain toward what this block needs to hit the target, applies it, then soft-clips so no
    /// output sample exceeds `ceiling` (~0.999). Mutates `samples` in place; a no-op for an empty buffer.
    public mutating func apply(to samples: inout [Float]) {
        guard !samples.isEmpty else { return }

        let rms = Self.rms(of: samples)
        let rmsDB = LevelMeter.dBFS(rms)

        // Target gain for this block. Below the noise floor we hold the current gain (don't chase silence
        // up to maxGain); otherwise close the dB gap to the target, clamped to [≈0, maxGain].
        let targetGain: Float
        if rmsDB <= noiseFloorDBFS {
            targetGain = currentGain
        } else {
            let gapDB = targetDBFS - rmsDB
            targetGain = min(max(pow(10, gapDB / 20), 0), maxGain)
        }

        // Asymmetric smoothing: ramp up slowly (attack), come down a bit faster (release).
        let coeff = targetGain > currentGain ? attack : release
        currentGain += (targetGain - currentGain) * coeff

        let gain = currentGain
        for i in samples.indices {
            samples[i] = Self.softClip(samples[i] * gain)
        }
    }

    /// Output ceiling — tanh asymptotes below 1.0; we scale by this so |out| < ~0.999 always.
    static let ceiling: Float = 0.999

    /// Soft-clip via `tanh`: linear for small inputs, smoothly saturating toward ±`ceiling` for large ones,
    /// so a hot signal rounds over instead of hard-clipping. Bounded because |tanh| < 1.
    static func softClip(_ x: Float) -> Float {
        ceiling * tanh(x)
    }

    static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sumSquares: Float = 0
        for s in samples { sumSquares += s * s }
        return (sumSquares / Float(samples.count)).squareRoot()
    }
}
