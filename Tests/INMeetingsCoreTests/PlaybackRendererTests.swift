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
