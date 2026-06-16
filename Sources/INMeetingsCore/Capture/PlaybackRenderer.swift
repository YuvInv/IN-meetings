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

    /// Produce the merged playback file. Audio-only (in-person / no video) → a level-balanced `audio.m4a`.
    /// Video call → mix the audio (aligned to the video via `offsets`, the A/V-sync fix) into a temp track,
    /// then **passthrough-mux** it with the captured HEVC video into `meeting.mp4` — copying the picture
    /// instead of re-encoding it, so the file stays the size the capture bitrate set (no HighestQuality bloat).
    public func render(tracks: [URL], offsets: [Double] = [], video: URL? = nil, to output: URL) async throws {
        guard let video else {
            try await mixAudio(tracks: tracks, offsets: offsets, to: output)   // audio-only → m4a
            return
        }
        let mixed = output.deletingLastPathComponent().appendingPathComponent(".mix-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: mixed) }
        try await mixAudio(tracks: tracks, offsets: offsets, to: mixed)        // 1. balanced audio on the video timeline
        try await muxPassthrough(video: video, audio: mixed, to: output)      // 2. copy video + audio → meeting.mp4
    }

    /// Mix the audio tracks into one level-balanced `.m4a` at `output`, each placed at its real `offsets[i]`
    /// (seconds, relative to the video / common clock) so the mix sits on the video's timeline. A track that
    /// started AFTER the video goes in at `+offset`; one that started BEFORE has its leading `-offset` trimmed.
    private func mixAudio(tracks: [URL], offsets: [Double], to output: URL) async throws {
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
            let offset = i < offsets.count ? offsets[i] : 0
            let sourceStart = offset < 0 ? CMTime(seconds: -offset, preferredTimescale: 600) : .zero
            let insertAt = offset > 0 ? CMTime(seconds: offset, preferredTimescale: 600) : .zero
            let length = CMTimeSubtract(dur, sourceStart)
            guard CMTimeCompare(length, .zero) > 0 else { continue }
            try dst.insertTimeRange(CMTimeRange(start: sourceStart, duration: length), of: src, at: insertAt)
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

    /// Mux a video + an (already-mixed) audio file into `output` **without re-encoding the video**
    /// (`Passthrough`), so the picture stays exactly the captured HEVC. Both start at t=0 (the mix already
    /// baked in the A/V offsets). Falls back to a re-encode only if passthrough fails.
    private func muxPassthrough(video: URL, audio: URL, to output: URL) async throws {
        let composition = AVMutableComposition()
        let vAsset = AVURLAsset(url: video)
        if let vSrc = try await vAsset.loadTracks(withMediaType: .video).first,
           let vDst = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try vDst.insertTimeRange(CMTimeRange(start: .zero, duration: try await vAsset.load(.duration)), of: vSrc, at: .zero)
        }
        let aAsset = AVURLAsset(url: audio)
        if let aSrc = try await aAsset.loadTracks(withMediaType: .audio).first,
           let aDst = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try aDst.insertTimeRange(CMTimeRange(start: .zero, duration: try await aAsset.load(.duration)), of: aSrc, at: .zero)
        }
        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetHEVCHighestQuality] {
            guard let export = AVAssetExportSession(asset: composition, presetName: preset) else { continue }
            try? FileManager.default.removeItem(at: output)
            export.outputURL = output
            export.outputFileType = .mp4
            await export.export()
            if export.status == .completed { return }
        }
        throw NSError(domain: "PlaybackRenderer", code: 3)
    }
}
