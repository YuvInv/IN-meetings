import AVFoundation
import CoreAudio
import Foundation

/// Captures the microphone to a WAV via `AVAudioEngine` (ADR-002, verified in P2).
///
/// Raw mic, no voice-processing (offline AEC is a later refinement). Needs the **Microphone** TCC grant.
/// Meters the peak level (via `LevelMeter`) so we can tell real audio from permission-denied silence.
/// Optionally records from a specific input device (`deviceUID`, else the system default) and applies
/// `AdaptiveGain` to the samples before writing (opt-in auto-leveling for quiet mics).
final class MicRecorder {
    let outputURL: URL
    /// Whole-capture peak (−120 if pure silence) — the RecordingController self-check reads this.
    var peak: Float { meter.peak }
    /// Latest per-buffer RMS (NOT the cumulative peak) — drives the live recording-HUD meter, which needs
    /// an instantaneous level that falls again, not a monotonically-rising max.
    private(set) var currentLevel: Float = 0
    /// "Pause" = mute: while true the buffer is still read + metered, but written as SILENCE so the WAV
    /// keeps a continuous timeline (a silent gap) and stays aligned with the system/video tracks.
    var muted = false
    private(set) var bufferCount = 0

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var meter = LevelMeter()
    /// Persistent UID of the input device to record from, or nil for the system default.
    private let deviceUID: String?
    /// Opt-in auto-leveling; nil leaves the raw mic untouched (the default).
    private var adaptiveGain: AdaptiveGain?

    init(outputURL: URL, deviceUID: String? = nil, adaptiveGain: AdaptiveGain? = nil) {
        self.outputURL = outputURL
        self.deviceUID = deviceUID
        self.adaptiveGain = adaptiveGain
    }

    /// Peak as dBFS over the whole capture (−120 if pure silence).
    var peakDB: Float { LevelMeter.dBFS(peak) }
    /// Instantaneous level as dBFS for the live HUD meter.
    var currentDB: Float { LevelMeter.dBFS(currentLevel) }

    /// Zero a float PCM buffer in place — used to write silence while muted (preserves the timeline).
    static func silence(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        for c in 0..<Int(buffer.format.channelCount) {
            memset(channels[c], 0, frames * MemoryLayout<Float>.size)
        }
    }

    func start() throws {
        let input = engine.inputNode
        if let deviceUID, let deviceID = Self.deviceID(forUID: deviceUID) {
            do {
                try setInputDevice(deviceID, on: input)
            } catch {
                // Best-effort: a device that can't be set falls back to the system default rather than
                // failing the recording (decision 4 — graceful degradation).
                captureLog.error("mic.start could not select device uid=\(deviceUID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        let fmt = input.outputFormat(forBus: 0)
        let auth = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
        captureLog.notice("mic.start fmt=\(fmt.sampleRate, privacy: .public)Hz ch=\(fmt.channelCount, privacy: .public) interleaved=\(fmt.isInterleaved, privacy: .public) micAuth=\(auth, privacy: .public) gain=\(self.adaptiveGain != nil, privacy: .public)")

        do {
            file = try AVAudioFile(forWriting: outputURL, settings: fmt.settings)
        } catch {
            throw CaptureError.fileOpenFailed(outputURL, error)
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, _ in
            guard let self else { return }
            self.bufferCount += 1
            if self.adaptiveGain != nil { self.applyGain(to: buf) }
            let (rms, _) = self.meter.process(buf)
            self.currentLevel = rms          // live HUD level (metered from the real signal)
            if self.muted { Self.silence(buf) }   // paused → write a silent gap, keep the timeline
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

    /// Apply adaptive gain to each channel of `buffer` in place (float buffers only; a no-op otherwise).
    private func applyGain(to buffer: AVAudioPCMBuffer) {
        guard adaptiveGain != nil, let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        for c in 0..<Int(buffer.format.channelCount) {
            let pointer = channels[c]
            var samples = Array(UnsafeBufferPointer(start: pointer, count: frames))
            adaptiveGain?.apply(to: &samples)
            samples.withUnsafeBufferPointer { src in
                pointer.update(from: src.baseAddress!, count: frames)
            }
        }
    }

    /// Set the recording device on the input node's audio unit (`kAudioOutputUnitProperty_CurrentDevice`),
    /// so we capture from the chosen mic rather than the system default.
    private func setInputDevice(_ deviceID: AudioDeviceID, on input: AVAudioInputNode) throws {
        var device = deviceID
        let status = AudioUnitSetProperty(
            input.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    /// Resolve a persistent device UID to its current `AudioDeviceID`, or nil if it isn't plugged in.
    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        let enumerator = AudioInputDeviceEnumerator()
        return enumerator.available().first(where: { $0.uid == uid })?.id
    }
}
