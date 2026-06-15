import AVFoundation
import Foundation

/// Renders the dual capture tracks into one level-balanced playback file (`audio.m4a`) so a listener
/// gets the natural "whole meeting" audio, not two separate channels (DECISIONS 2026-06-14). The raw
/// mic/system WAVs stay as the lossless transcription inputs.
public struct PlaybackRenderer: Sendable {
    public static let outputName = "audio.m4a"
    public init() {}

    /// Per-track playback volumes that equalize perceived loudness: the louder track stays at 1.0, the
    /// quieter is boosted toward it (capped 4×). A silent track (RMS≈0) is left at 1.0 — boosting it
    /// would just amplify the noise floor.
    public static func balancedVolumes(micRMS: Float, systemRMS: Float) -> (mic: Float, system: Float) {
        let hi = max(micRMS, systemRMS)
        func vol(_ rms: Float) -> Float {
            guard rms > 1e-4, hi > 1e-4 else { return 1.0 }
            return min(max(hi / rms, 1.0), 4.0)
        }
        return (vol(micRMS), vol(systemRMS))
    }

    /// Mean RMS of a mono/interleaved WAV via AVAudioFile (chunked, never loads the whole file).
    public static func rms(of url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(min(file.length, 48000 * 60 * 30))
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return 0 }
        try file.read(into: buf)
        guard let ch = buf.floatChannelData else { return 0 }
        var sum: Float = 0; let n = Int(buf.frameLength)
        for i in 0..<n { let s = ch[0][i]; sum += s * s }
        return n > 0 ? (sum / Float(n)).squareRoot() : 0
    }

    /// Mix the tracks into `output` (`.m4a`, AAC), level-balanced. One track → straight transcode.
    public func render(tracks: [URL], to output: URL) async throws {
        let composition = AVMutableComposition()
        let audioMix = AVMutableAudioMix()
        var params: [AVMutableAudioMixInputParameters] = []
        let rmses = tracks.map { (try? Self.rms(of: $0)) ?? 0 }
        let volumes: [Float] = tracks.count == 2
            ? { let (m, s) = Self.balancedVolumes(micRMS: rmses[0], systemRMS: rmses[1]); return [m, s] }()
            : Array(repeating: 1.0, count: tracks.count)
        for (i, url) in tracks.enumerated() {
            let asset = AVURLAsset(url: url)
            guard let src = try await asset.loadTracks(withMediaType: .audio).first,
                  let dst = composition.addMutableTrack(withMediaType: .audio,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let dur = try await asset.load(.duration)
            try dst.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: src, at: .zero)
            let p = AVMutableAudioMixInputParameters(track: dst)
            p.setVolume(volumes[i], at: .zero)
            params.append(p)
        }
        audioMix.inputParameters = params
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "PlaybackRenderer", code: 1)
        }
        try? FileManager.default.removeItem(at: output)
        export.outputURL = output
        export.outputFileType = .m4a
        export.audioMix = audioMix
        await export.export()
        if export.status != .completed { throw export.error ?? NSError(domain: "PlaybackRenderer", code: 2) }
    }
}
