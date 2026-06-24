import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Records a video call through **one ScreenCaptureKit stream** — `.screen` (window video, HEVC),
/// `.audio` (system audio = the remote participants, "Them"), and `.microphone` ("Me") — all on SCK's
/// single capture clock (DECISIONS 2026-06-16, amends ADR-002). Because the three streams share one
/// clock, the merged `meeting.mp4` is A/V-synced *by construction* (no cross-clock skew or drift, the bug
/// the old separate-capture + t=0 merge had).
///
/// Keeps the on-disk contract identical to the audio path — `mic.wav` + `system.wav` (the dual-track
/// transcription inputs / the moat) + `video.mov` — so the Python pipeline and Drive upload are unchanged.
/// Each audio type goes to its **own** file (writing `.audio` and `.microphone` to one sink is the known
/// `captureMicrophone` corruption pitfall). Returns each stream's first timestamp so `PlaybackRenderer`
/// aligns the mux at the real offsets, not t=0.
///
/// Needs the **Screen Recording** + **Microphone** grants. `start()` throws so the caller can fall back to
/// the audio-only path. `@unchecked Sendable`: writer/file setup happens before `startCapture()` (no
/// callbacks yet); the sample queue is serial; `stop()` reads shared state under `lock` after the queue drains.
@available(macOS 14.2, *)
final class ScreenCaptureKitRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Output {
        let video: URL?
        let mic: URL?
        let system: URL?
        let micPeakDB: Float
        let systemPeakDB: Float
        /// Start offset (seconds) of each audio track relative to the first video frame, on SCK's clock.
        /// nil when there was no video. Used to align the mux; positive = audio started after video.
        let micOffset: Double?
        let systemOffset: Double?
    }

    /// Capture sizing — a meeting doesn't need 4K/30fps. ~720p @ 15 fps @ 2 Mbps HEVC keeps faces +
    /// screen-shares legible while a 22-min call is ~300 MB (vs ~1.9 GB at 2× retina / default bitrate).
    static let maxVideoLongEdge = 1280
    static let videoBitrate = 2_000_000
    static let videoFPS: Int32 = 15

    private let directory: URL
    private let bundleID: String
    /// Persistent UID of the mic device to capture (decision 5: best-effort on the SCK path), or nil for the
    /// system default. Threaded into `microphoneCaptureDeviceID` on macOS 15+.
    private let micDeviceUID: String?
    private var videoURL: URL { directory.appendingPathComponent("video.mov") }
    private var micURL: URL { directory.appendingPathComponent("mic.wav") }
    private var systemURL: URL { directory.appendingPathComponent("system.wav") }

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var micFile: AVAudioFile?
    private var systemFile: AVAudioFile?
    private let sampleQueue = DispatchQueue(label: "com.in-venture.in-meetings.callstream")
    private let lock = NSLock()

    private var sessionStarted = false
    private var framesAppended = 0
    private var videoStart: CMTime?
    private var micStart: CMTime?
    private var systemStart: CMTime?
    private var micPeak: Float = 0
    private var systemPeak: Float = 0

    init(directory: URL, bundleID: String, micDeviceUID: String? = nil) {
        self.directory = directory
        self.bundleID = bundleID
        self.micDeviceUID = micDeviceUID
    }

    /// Find the call window, configure a stream that captures video + system audio + mic, and start.
    /// Throws (`.screenRecordingDenied` / `.callWindowNotFound` / `.videoWriterFailed`) so the caller can
    /// fall back to the audio-only path.
    func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.screenRecordingDenied
        }
        guard let window = Self.bestWindow(in: content, bundleID: bundleID) else {
            throw CaptureError.callWindowNotFound(bundleID)
        }

        // Downscale to ~720p (long edge), never upscale — a meeting doesn't need the native 2×-retina size.
        let longEdge = max(window.frame.width, window.frame.height)
        let fit = min(1.0, CGFloat(Self.maxVideoLongEdge) / longEdge)
        let w = Self.evenClamp(window.frame.width * fit, max: Self.maxVideoLongEdge)
        let h = Self.evenClamp(window.frame.height * fit, max: Self.maxVideoLongEdge)

        let config = SCStreamConfiguration()
        config.capturesAudio = true            // system audio of the call window = "Them"
        config.channelCount = 1                // mono — fine for ASR + meeting playback; halves the audio
        if #available(macOS 15.0, *) {
            config.captureMicrophone = true    // the user's mic = "Me" (delivered as a separate stream)
            // Best-effort device selection (decision 5): if the user picked a mic, capture from it; nil
            // leaves SCK on the system default. Adaptive gain is NOT applied on the SCK path — only on the
            // audio path's `MicRecorder` — so a video call records the raw chosen mic.
            if let micDeviceUID { config.microphoneCaptureDeviceID = micDeviceUID }
        }
        config.width = w
        config.height = h
        config.minimumFrameInterval = CMTime(value: 1, timescale: Self.videoFPS)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6

        let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Self.videoBitrate,
                AVVideoExpectedSourceFrameRateKey: Self.videoFPS,
                AVVideoMaxKeyFrameIntervalKey: Self.videoFPS * 4,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { throw CaptureError.videoWriterFailed(nil) }
        writer.add(videoInput)
        guard writer.startWriting() else { throw CaptureError.videoWriterFailed(writer.error) }
        self.writer = writer
        self.videoInput = videoInput

        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window),
                              configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        if #available(macOS 15.0, *) {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
        }
        self.stream = stream
        try await stream.startCapture()
        captureLog.notice("callstream.start app=\(self.bundleID, privacy: .public) \(w, privacy: .public)x\(h, privacy: .public)")
    }

    /// Stop, finalize the video file + close the WAVs, and report what was captured + the A/V offsets.
    func stop() async -> Output {
        try? await stream?.stopCapture()
        stream = nil
        let (started, frames, vStart, mStart, sStart, mPeak, sPeak) = snapshot()

        videoInput?.markAsFinished()
        var videoOut: URL?
        if started, frames > 0 {
            await writer?.finishWriting()
            if writer?.status == .completed { videoOut = videoURL }
        } else {
            writer?.cancelWriting()
        }
        if videoOut == nil { try? FileManager.default.removeItem(at: videoURL) }
        micFile = nil       // flush/close the WAVs
        systemFile = nil

        func offset(_ s: CMTime?) -> Double? {
            guard let s, let v = vStart else { return nil }
            return (s - v).seconds
        }
        let mic = FileManager.default.fileExists(atPath: micURL.path) ? micURL : nil
        let system = FileManager.default.fileExists(atPath: systemURL.path) ? systemURL : nil
        captureLog.notice("callstream.stop frames=\(frames, privacy: .public) video=\(videoOut != nil, privacy: .public) micPeak=\(mPeak > 0 ? 20*log10(mPeak) : -120, privacy: .public)dB sysPeak=\(sPeak > 0 ? 20*log10(sPeak) : -120, privacy: .public)dB")
        return Output(video: videoOut, mic: mic, system: system,
                      micPeakDB: mPeak > 0 ? 20 * log10(mPeak) : -120,
                      systemPeakDB: sPeak > 0 ? 20 * log10(sPeak) : -120,
                      micOffset: videoOut != nil ? offset(mStart) : nil,
                      systemOffset: videoOut != nil ? offset(sStart) : nil)
    }

    /// Synchronous locked read of the capture state (NSLock can't be held in `stop()`'s async context).
    private func snapshot() -> (Bool, Int, CMTime?, CMTime?, CMTime?, Float, Float) {
        lock.lock(); defer { lock.unlock() }
        return (sessionStarted, framesAppended, videoStart, micStart, systemStart, micPeak, systemPeak)
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if type == .screen {
            appendVideo(sampleBuffer)
        } else if type == .audio {
            appendAudio(sampleBuffer, system: true)
        } else if #available(macOS 15.0, *), type == .microphone {
            appendAudio(sampleBuffer, system: false)
        }
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        // Only append "complete" frames — skip idle/blank deltas SCK emits when nothing on screen changed.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[SCStreamFrameInfo.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete else { return }
        guard let writer, let videoInput, writer.status == .writing else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        lock.lock()
        if !sessionStarted {
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
            videoStart = pts
        }
        lock.unlock()
        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
            lock.lock(); framesAppended += 1; lock.unlock()
        }
    }

    /// Write an audio buffer to its WAV (lazily creating the file from the buffer's format) + meter peak.
    private func appendAudio(_ sampleBuffer: CMSampleBuffer, system: Bool) {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: fmtDesc)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        pcm.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList) == noErr else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var peak: Float = 0
        if let ch = pcm.floatChannelData {
            for c in 0..<Int(format.channelCount) {
                let p = ch[c]; for i in 0..<Int(frames) { let v = abs(p[i]); if v > peak { peak = v } }
            }
        }
        lock.lock()
        if system {
            if systemStart == nil { systemStart = pts }
            if peak > systemPeak { systemPeak = peak }
            if systemFile == nil { systemFile = try? AVAudioFile(forWriting: systemURL, settings: format.settings,
                                                                 commonFormat: format.commonFormat, interleaved: format.isInterleaved) }
            try? systemFile?.write(from: pcm)
        } else {
            if micStart == nil { micStart = pts }
            if peak > micPeak { micPeak = peak }
            if micFile == nil { micFile = try? AVAudioFile(forWriting: micURL, settings: format.settings,
                                                           commonFormat: format.commonFormat, interleaved: format.isInterleaved) }
            try? micFile?.write(from: pcm)
        }
        lock.unlock()
    }

    // MARK: - Helpers

    /// The largest on-screen window owned by `bundleID` (the call window). nil if the app has none.
    static func bestWindow(in content: SCShareableContent, bundleID: String) -> SCWindow? {
        content.windows
            .filter { $0.owningApplication?.bundleIdentifier == bundleID && $0.isOnScreen }
            .max { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) }
    }

    /// Round to an even pixel count (HEVC needs even dimensions), clamped to `[2, maximum]`.
    static func evenClamp(_ value: CGFloat, max maximum: Int) -> Int {
        let v = Swift.min(Swift.max(Int(value.rounded()), 2), maximum)
        return v - (v % 2)
    }
}
