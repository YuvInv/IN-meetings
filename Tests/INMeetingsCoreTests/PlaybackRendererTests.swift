import AVFoundation
import XCTest
@testable import INMeetingsCore

final class PlaybackRendererTests: XCTestCase {
    func testBalancedVolumesEqualizesQuieterTrack() {
        let (mic, sys) = PlaybackRenderer.balancedVolumes(micRMS: 0.1, systemRMS: 0.025)
        XCTAssertEqual(mic, 1.0, accuracy: 0.001)   // louder stays at unity
        XCTAssertEqual(sys, 4.0, accuracy: 0.001)   // quieter boosted, capped at 4×
    }
    func testBalancedVolumesEqualLevels() {
        let (mic, sys) = PlaybackRenderer.balancedVolumes(micRMS: 0.08, systemRMS: 0.08)
        XCTAssertEqual(mic, 1.0, accuracy: 0.001)
        XCTAssertEqual(sys, 1.0, accuracy: 0.001)
    }
    func testBalancedVolumesSilentTrackStaysQuiet() {
        let (_, sys) = PlaybackRenderer.balancedVolumes(micRMS: 0.1, systemRMS: 0.0)
        XCTAssertEqual(sys, 1.0, accuracy: 0.001)   // no signal → don't amplify noise floor
    }

    func testRenderProducesM4A() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let mic = try writeSine(dir.appendingPathComponent("mic.wav"), seconds: 1.0, freq: 220, rate: 24000)
        let sys = try writeSine(dir.appendingPathComponent("system.wav"), seconds: 1.0, freq: 440, rate: 48000)
        let out = dir.appendingPathComponent(PlaybackRenderer.outputName)
        try await PlaybackRenderer().render(tracks: [mic, sys], to: out)
        let size = try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 1000)
        let audioTracks = try await AVURLAsset(url: out).load(.tracks).filter { $0.mediaType == .audio }
        XCTAssertEqual(audioTracks.count, 1)
    }

    /// The V1 video path: a window video + the two audio tracks mux into one `meeting.mp4` carrying both
    /// a video and an audio track.
    func testRenderMuxesVideoAndAudioIntoMP4() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let mic = try writeSine(dir.appendingPathComponent("mic.wav"), seconds: 1.0, freq: 220, rate: 24000)
        let sys = try writeSine(dir.appendingPathComponent("system.wav"), seconds: 1.0, freq: 440, rate: 48000)
        let video = try await writeBlankVideo(dir.appendingPathComponent("video.mov"), seconds: 1.0)
        let out = dir.appendingPathComponent(PlaybackRenderer.videoOutputName)
        try await PlaybackRenderer().render(tracks: [mic, sys], video: video, to: out)

        let tracks = try await AVURLAsset(url: out).load(.tracks)
        XCTAssertEqual(tracks.filter { $0.mediaType == .video }.count, 1)   // muxed video
        XCTAssertEqual(tracks.filter { $0.mediaType == .audio }.count, 1)   // + the balanced audio
    }

    /// The A/V sync fix: a track given a +0.5s offset is placed 0.5s into the timeline, so a 1s+1s pair
    /// spans 1.5s (not merged at t=0). Proves the unified-capture offsets are honored by the mux.
    func testRenderAppliesPerTrackOffset() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try writeSine(dir.appendingPathComponent("a.wav"), seconds: 1.0, freq: 220, rate: 48000)
        let b = try writeSine(dir.appendingPathComponent("b.wav"), seconds: 1.0, freq: 440, rate: 48000)
        let out = dir.appendingPathComponent("audio.m4a")
        try await PlaybackRenderer().render(tracks: [a, b], offsets: [0, 0.5], to: out)
        let dur = try await AVURLAsset(url: out).load(.duration)
        XCTAssertEqual(dur.seconds, 1.5, accuracy: 0.12)   // 0.5s offset shifts the second track out
    }

    /// Writes a short H.264 video (solid black frames) at `url` via AVAssetWriter, returning the URL.
    private func writeBlankVideo(_ url: URL, seconds: Double, fps: Int32 = 10,
                                 size: CGSize = CGSize(width: 160, height: 120)) async throws -> URL {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        guard writer.canAdd(input) else { throw NSError(domain: "writeBlankVideo", code: 1) }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for i in 0..<Int(Double(fps) * seconds) {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &pb)
            if let pb { adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps)) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    /// Writes a mono float32 sine WAV at `url` using AVAudioFile, returning the URL.
    private func writeSine(_ url: URL, seconds: Double, freq: Double, rate: Double) throws -> URL {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let frameCount = AVAudioFrameCount(seconds * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount),
              let channel = buffer.floatChannelData else {
            throw NSError(domain: "writeSine", code: 1)
        }
        buffer.frameLength = frameCount
        let twoPiF = 2.0 * Double.pi * freq
        for i in 0..<Int(frameCount) {
            channel[0][i] = Float(0.5 * sin(twoPiF * Double(i) / rate))
        }
        try file.write(from: buffer)
        return url
    }
}
