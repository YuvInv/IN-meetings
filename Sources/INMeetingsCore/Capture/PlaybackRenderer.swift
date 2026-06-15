import AVFoundation
import Foundation

/// Renders the dual capture tracks into one level-balanced playback file (`audio.m4a`) so a listener
/// gets the natural "whole meeting" audio, not two separate channels (DECISIONS 2026-06-14). The raw
/// mic/system WAVs stay as the lossless transcription inputs.
public struct PlaybackRenderer: Sendable {
    /// The audio-only merged playback file (in-person, or a call recorded without video).
    public static let outputName = "audio.m4a"
    /// The video merged playback file — call-window video + the level-balanced audio, muxed (V1 video).
    public static let videoOutputName = "meeting.mp4"
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

    /// Mix the audio tracks into `output`, level-balanced; when `video` is given, mux it in too so the
    /// output is one watchable `meeting.mp4` (window video + balanced audio). One audio track → no
    /// balancing. Audio and video both start at t=0 (they were captured together within the same Start).
    public func render(tracks: [URL], video: URL? = nil, to output: URL) async throws {
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

        var hasVideo = false
        if let video {
            let vAsset = AVURLAsset(url: video)
            if let vSrc = try? await vAsset.loadTracks(withMediaType: .video).first,
               let vDst = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid) {
                let vDur = (try? await vAsset.load(.duration)) ?? .zero
                try vDst.insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: vSrc, at: .zero)
                hasVideo = true
            }
        }

        let preset = hasVideo ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetAppleM4A
        var session = AVAssetExportSession(asset: composition, presetName: preset)
        if session == nil, hasVideo {   // some configs lack the HEVC preset — fall back to H.264
            session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        }
        guard let export = session else { throw NSError(domain: "PlaybackRenderer", code: 1) }
        try? FileManager.default.removeItem(at: output)
        export.outputURL = output
        export.outputFileType = hasVideo ? .mp4 : .m4a
        export.audioMix = audioMix
        await export.export()
        if export.status != .completed { throw export.error ?? NSError(domain: "PlaybackRenderer", code: 2) }
    }
}
