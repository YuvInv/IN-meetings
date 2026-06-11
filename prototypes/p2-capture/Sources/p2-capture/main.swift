// P2 — dual-track capture prototype (ADR-002).
//
// Captures TWO separate tracks with NO virtual driver and NO Screen Recording permission:
//   • system/remote audio  → system.wav   via a Core Audio process tap (CATapDescription,
//                                            macOS 14.2+) on an aggregate device
//   • microphone           → mic.wav      via AVAudioEngine
//
// What this de-risks (verify on macOS 26):
//   1. Tap capture works with ONLY "System Audio Recording Only" TCC (no Screen Recording).
//   2. Whether the monthly re-approval nag appears for an audio-tap-only app (it shouldn't).
//   3. Two clean separate tracks (the basis for Me/Them attribution).
//
// Run:  swift run p2-capture [seconds]      (default 15)
// First run prompts for Microphone + System Audio Recording permission. Play audio (e.g. a
// YouTube video) and talk into the mic during capture, then inspect the two WAVs.

import AVFoundation
import CoreAudio
import Foundation

let durationSec = Double(CommandLine.arguments.dropFirst().first ?? "15") ?? 15
let outDir = FileManager.default.currentDirectoryPath
let systemURL = URL(fileURLWithPath: outDir).appendingPathComponent("system.wav")
let micURL = URL(fileURLWithPath: outDir).appendingPathComponent("mic.wav")

func fail(_ msg: String) -> Never { fputs("ERROR: \(msg)\n", stderr); exit(1) }
func check(_ status: OSStatus, _ what: String) {
    if status != noErr { fail("\(what) failed (OSStatus \(status))") }
}

// MARK: - System audio via Core Audio process tap

@available(macOS 14.2, *)
final class SystemTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var format: AVAudioFormat?

    func start() {
        // 1. Global stereo tap excluding nothing (whole system mix). For per-process, pass PIDs->objectIDs.
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted

        check(AudioHardwareCreateProcessTap(desc, &tapID), "AudioHardwareCreateProcessTap")
        guard tapID != kAudioObjectUnknown else { fail("tap not created — permission likely denied") }

        // 2. Tap stream format → AVAudioFormat for the output file.
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        check(AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &size, &asbd), "get tap format")
        guard let fmt = AVAudioFormat(streamDescription: &asbd) else { fail("bad tap format") }
        format = fmt

        // 3. Private aggregate device wrapping the tap.
        let aggUID = UUID().uuidString
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "IN-Meetings-P2-Tap",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: desc.uuid.uuidString,
                 kAudioSubTapDriftCompensationKey: true],
            ],
        ]
        check(AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggregateID),
              "AudioHardwareCreateAggregateDevice")

        file = try? AVAudioFile(forWriting: systemURL, settings: fmt.settings)
        guard file != nil else { fail("cannot open \(systemURL.lastPathComponent)") }

        // 4. IOProc: wrap the tap's AudioBufferList and write it.
        let ioBlock: AudioDeviceIOBlock = { [weak self] _, inInputData, _, _, _ in
            guard let self, let fmt = self.format,
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt,
                                             bufferListNoCopy: inInputData,
                                             deallocator: nil) else { return }
            try? self.file?.write(from: buf)
        }
        check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, ioBlock),
              "AudioDeviceCreateIOProcIDWithBlock")
        check(AudioDeviceStart(aggregateID, procID), "AudioDeviceStart")
        print("• system tap started → \(systemURL.lastPathComponent) (format: \(fmt.sampleRate)Hz \(fmt.channelCount)ch)")
    }

    func stop() {
        if let procID { AudioDeviceStop(aggregateID, procID); AudioDeviceDestroyIOProcID(aggregateID, procID) }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        file = nil
        print("• system tap stopped")
    }
}

// MARK: - Microphone via AVAudioEngine

final class MicCapture {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    func start() {
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)               // raw mic, no voice-processing (ADR-002)
        file = try? AVAudioFile(forWriting: micURL, settings: fmt.settings)
        guard file != nil else { fail("cannot open \(micURL.lastPathComponent)") }
        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, _ in
            try? self?.file?.write(from: buf)
        }
        do { try engine.start() } catch { fail("AVAudioEngine.start: \(error.localizedDescription)") }
        print("• mic started → \(micURL.lastPathComponent) (format: \(fmt.sampleRate)Hz \(fmt.channelCount)ch)")
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        print("• mic stopped")
    }
}

// MARK: - Run

if #available(macOS 14.2, *) {
    print("P2 dual-track capture — \(Int(durationSec))s. Play some audio and talk into the mic.")
    let tap = SystemTap()
    let mic = MicCapture()
    tap.start()
    mic.start()
    Thread.sleep(forTimeInterval: durationSec)
    mic.stop()
    tap.stop()

    for url in [systemURL, micURL] {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let bytes = attrs[.size] as? Int {
            print("✔ \(url.lastPathComponent): \(bytes / 1024) KB")
        }
    }
    print("Done. Inspect the two WAVs — system.wav should hold the played audio, mic.wav your voice.")
} else {
    fail("Core Audio process taps require macOS 14.2+")
}
