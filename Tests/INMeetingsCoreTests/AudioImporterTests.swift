import XCTest
import AVFoundation
@testable import INMeetingsCore

final class AudioImporterTests: XCTestCase {
    /// Synthesize a short stereo 48 kHz WAV tone we can feed to the importer.
    private func makeStereoWav(at url: URL, seconds: Double = 0.5) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(48000 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for ch in 0..<2 {
            let p = buffer.floatChannelData![ch]
            for i in 0..<Int(frames) { p[i] = sinf(2 * .pi * 440 * Float(i) / 48000) * 0.2 }
        }
        try file.write(from: buffer)
    }

    func testConvertsToSixteenKMono() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let src = tmp.appendingPathComponent("import-src-\(UUID().uuidString).wav")
        let out = tmp.appendingPathComponent("import-out-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: out) }
        try makeStereoWav(at: src)

        try await AudioImporter.convertToWav16kMono(src, to: out)

        let result = try AVAudioFile(forReading: out)
        XCTAssertEqual(result.fileFormat.sampleRate, 16000, accuracy: 0.5)
        XCTAssertEqual(result.fileFormat.channelCount, 1)
        XCTAssertGreaterThan(result.length, 0)
    }

    func testThrowsWhenNoAudioTrack() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let bogus = tmp.appendingPathComponent("not-audio-\(UUID().uuidString).wav")
        try Data([0x00, 0x01, 0x02]).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }
        do {
            try await AudioImporter.convertToWav16kMono(bogus, to: tmp.appendingPathComponent("x.wav"))
            XCTFail("expected an error for a file with no audio track")
        } catch { /* expected */ }
    }
}
