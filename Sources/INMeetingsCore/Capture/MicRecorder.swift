import AVFoundation
import Foundation

/// Captures the microphone to a WAV via `AVAudioEngine` (ADR-002, verified in P2).
///
/// Raw mic, no voice-processing (offline AEC is a later refinement). Needs the **Microphone** TCC grant.
/// Meters the peak level so we can tell real audio from permission-denied silence.
final class MicRecorder {
    let outputURL: URL
    private(set) var peak: Float = 0
    private(set) var bufferCount = 0

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    init(outputURL: URL) { self.outputURL = outputURL }

    /// Peak as dBFS over the whole capture (−120 if pure silence).
    var peakDB: Float { peak > 0 ? 20 * log10(peak) : -120 }

    func start() throws {
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        let auth = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
        captureLog.notice("mic.start fmt=\(fmt.sampleRate, privacy: .public)Hz ch=\(fmt.channelCount, privacy: .public) interleaved=\(fmt.isInterleaved, privacy: .public) micAuth=\(auth, privacy: .public)")

        do {
            file = try AVAudioFile(forWriting: outputURL, settings: fmt.settings)
        } catch {
            throw CaptureError.fileOpenFailed(outputURL, error)
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, _ in
            guard let self else { return }
            self.bufferCount += 1
            if let channels = buf.floatChannelData {
                let frames = Int(buf.frameLength)
                for c in 0..<Int(buf.format.channelCount) {
                    let samples = channels[c]
                    for i in 0..<frames { let v = abs(samples[i]); if v > self.peak { self.peak = v } }
                }
            }
            try? self.file?.write(from: buf)
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            file = nil
            throw CaptureError.micEngineFailed(error)
        }
        captureLog.notice("mic.start engineRunning=\(self.engine.isRunning, privacy: .public)")
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil   // flushes/closes the WAV
        captureLog.notice("mic.stop buffers=\(self.bufferCount, privacy: .public) peak=\(self.peakDB, privacy: .public)dB")
    }
}
