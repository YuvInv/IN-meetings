import AVFoundation
import CoreAudio
import Foundation

/// Errors surfaced by the capture pipeline.
public enum CaptureError: Error, CustomStringConvertible {
    case tapCreationFailed(OSStatus)
    case systemAudioPermissionDenied
    case badTapFormat
    case aggregateCreationFailed(OSStatus)
    case ioProcFailed(OSStatus)
    case fileOpenFailed(URL, Error)
    case micEngineFailed(Error)
    case screenRecordingDenied
    case callWindowNotFound(String)
    case videoWriterFailed(Error?)

    public var description: String {
        switch self {
        case .tapCreationFailed(let s): return "Could not create the system-audio tap (OSStatus \(s))."
        case .systemAudioPermissionDenied:
            return "System Audio Recording permission is required to capture the other participants."
        case .badTapFormat: return "The system-audio tap returned an unreadable format."
        case .aggregateCreationFailed(let s): return "Could not create the capture device (OSStatus \(s))."
        case .ioProcFailed(let s): return "Could not start the system-audio stream (OSStatus \(s))."
        case .fileOpenFailed(let url, let e): return "Could not open \(url.lastPathComponent): \(e.localizedDescription)."
        case .micEngineFailed(let e): return "Microphone capture failed: \(e.localizedDescription)."
        case .screenRecordingDenied:
            return "Screen Recording permission is required to record the call video."
        case .callWindowNotFound(let id): return "No on-screen window found for the call app (\(id))."
        case .videoWriterFailed(let e): return "Could not start the video writer: \(e?.localizedDescription ?? "unknown")."
        }
    }
}

/// Captures system/remote audio to a WAV via a Core Audio process tap (ADR-002, verified in P2).
///
/// macOS 14.2+. Needs the **System Audio Recording** TCC grant (no Screen Recording). Pins the output
/// file to the tap's exact interleaved-float32 format — the fix for the `write(from:)` −50 bug that
/// otherwise yields a silent file. A peak meter distinguishes real audio from permission-denied silence.
@available(macOS 14.2, *)
final class SystemAudioTap {
    let outputURL: URL
    private(set) var ioCalls = 0
    private(set) var framesWritten: Int64 = 0
    private(set) var peak: Float = 0
    private(set) var lastWriteError: String?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var format: AVAudioFormat?

    init(outputURL: URL) { self.outputURL = outputURL }

    /// True once the tap has stopped if it only ever saw digital silence (permission likely denied).
    var capturedSilence: Bool { peak < 0.0001 }

    /// Peak as dBFS over the whole capture (−120 if pure silence).
    var peakDB: Float { peak > 0 ? 20 * log10(peak) : -120 }

    func start() throws {
        // Whole-system stereo mix tap (for per-process, pass the PIDs to exclude/include).
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted

        let createStatus = AudioHardwareCreateProcessTap(desc, &tapID)
        guard createStatus == noErr else { throw CaptureError.tapCreationFailed(createStatus) }
        guard tapID != kAudioObjectUnknown else { throw CaptureError.systemAudioPermissionDenied }

        // Tap stream format → AVAudioFormat for the output file.
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let fmtStatus = AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &size, &asbd)
        guard fmtStatus == noErr, let fmt = AVAudioFormat(streamDescription: &asbd) else {
            throw CaptureError.badTapFormat
        }
        format = fmt
        captureLog.notice("tap.start fmt=\(fmt.sampleRate, privacy: .public)Hz ch=\(fmt.channelCount, privacy: .public) interleaved=\(fmt.isInterleaved, privacy: .public)")

        // Private aggregate device wrapping the tap.
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "IN-Meetings-Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: desc.uuid.uuidString,
                 kAudioSubTapDriftCompensationKey: true],
            ],
        ]
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggregateID)
        guard aggStatus == noErr else { throw CaptureError.aggregateCreationFailed(aggStatus) }

        // Pin the file to the tap's EXACT format (incl. interleaving) so write(from:) doesn't fail −50.
        do {
            file = try AVAudioFile(forWriting: outputURL,
                                   settings: fmt.settings,
                                   commonFormat: fmt.commonFormat,
                                   interleaved: fmt.isInterleaved)
        } catch {
            throw CaptureError.fileOpenFailed(outputURL, error)
        }

        // IOProc: wrap the tap's AudioBufferList and write it; meter the peak for the silence check.
        let ioBlock: AudioDeviceIOBlock = { [weak self] _, inInputData, _, _, _ in
            guard let self else { return }
            self.ioCalls += 1
            guard let fmt = self.format,
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt,
                                             bufferListNoCopy: inInputData,
                                             deallocator: nil) else { return }
            self.framesWritten += Int64(buf.frameLength)
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            for b in abl {
                if let data = b.mData {
                    let n = Int(b.mDataByteSize) / MemoryLayout<Float>.size
                    let p = data.assumingMemoryBound(to: Float.self)
                    for i in 0..<n { let v = abs(p[i]); if v > self.peak { self.peak = v } }
                }
            }
            do { try self.file?.write(from: buf) }
            catch { if self.lastWriteError == nil { self.lastWriteError = "\(error)" } }
        }
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, ioBlock)
        guard procStatus == noErr else { throw CaptureError.ioProcFailed(procStatus) }
        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else { throw CaptureError.ioProcFailed(startStatus) }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        file = nil   // flushes/closes the WAV
        captureLog.notice("tap.stop ioCalls=\(self.ioCalls, privacy: .public) frames=\(self.framesWritten, privacy: .public) peak=\(self.peakDB, privacy: .public)dB writeError=\(self.lastWriteError ?? "none", privacy: .public)")
    }
}
