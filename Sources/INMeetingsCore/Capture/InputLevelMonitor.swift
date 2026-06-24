import AVFoundation
import CoreAudio
import Foundation
import Observation

/// Drives the live input-level (VU) meter in Settings: a short-lived `AVAudioEngine` tap on the chosen
/// input device that publishes `currentDB` (no file written). The Settings view starts it on appear and
/// stops it on disappear. The live tap itself is live-verify; the dB math lives in `LevelMeter`, so the
/// numbers it publishes are unit-tested.
@MainActor
@Observable
public final class InputLevelMonitor {
    /// Current input level in dBFS (−120 when silent / not running). Drives the VU bar.
    public private(set) var currentDB: Float = -120
    public private(set) var isRunning = false

    private var engine: AVAudioEngine?

    public init() {}

    /// Start metering the resolved input device (nil → system default). Idempotent: a running monitor is
    /// stopped first so re-selecting a device re-points the tap.
    public func start(deviceUID: String?) {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceUID,
           let deviceID = AudioInputDeviceEnumerator().available().first(where: { $0.uid == deviceUID })?.id,
           let unit = input.audioUnit {
            var device = deviceID
            let status = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &device, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr {
                captureLog.error("levelmonitor.start could not select device uid=\(deviceUID, privacy: .public) status=\(status, privacy: .public)")
            }
        }

        let fmt = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, _ in
            // Per-buffer RMS (not the running peak) so the bar tracks the live signal and falls back to
            // quiet, rather than holding the loudest sample ever seen.
            var meter = LevelMeter()
            let level = meter.process(buf)
            let db = LevelMeter.dBFS(level.rms)
            Task { @MainActor [weak self] in self?.currentDB = db }
        }
        do {
            try engine.start()
            self.engine = engine
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            captureLog.error("levelmonitor.start engine failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        isRunning = false
        currentDB = -120
    }
}
