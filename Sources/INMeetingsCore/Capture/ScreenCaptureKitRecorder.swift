import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Records the detected call app's window as a **window-only, video-only HEVC** stream (ScreenCaptureKit),
/// written to `video.mov` (DECISIONS 2026-06-14). Audio stays on the Core Audio dual-track path
/// (`capturesAudio = false`) — this is purely the picture (participants + shared screen). Scoped to the
/// call app's window so unrelated/sensitive screen content stays out (privacy, ADR-010).
///
/// Needs the **Screen Recording** TCC grant. Degrades gracefully — throwing `CaptureError` so the caller
/// keeps the audio recording — when permission is denied or the call app has no on-screen window.
/// `@unchecked Sendable`: mutable state is set before `startCapture()` (no callbacks yet) and the frame
/// counters are guarded by `lock`; `stopCapture()` drains the sample queue before the file is finalized.
@available(macOS 14.2, *)
final class ScreenCaptureKitRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let outputURL: URL
    private let bundleID: String

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private let sampleQueue = DispatchQueue(label: "com.in-venture.in-meetings.video")
    private let lock = NSLock()
    private var sessionStarted = false
    private var framesAppended = 0

    init(outputURL: URL, bundleID: String) {
        self.outputURL = outputURL
        self.bundleID = bundleID
    }

    /// Find the call app's largest on-screen window, start an HEVC writer, and begin capture. Throws
    /// `.screenRecordingDenied` / `.callWindowNotFound` / `.videoWriterFailed` so the caller can degrade
    /// to audio-only.
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

        let scale = 2.0   // capture near retina resolution; SCK renders the window content into w×h
        let w = Self.evenClamp(window.frame.width * scale, max: 3840)
        let h = Self.evenClamp(window.frame.height * scale, max: 2160)

        let config = SCStreamConfiguration()
        config.capturesAudio = false           // audio stays on the Core Audio dual-track path (ADR-002)
        config.width = w
        config.height = h
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)   // up to 30 fps
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CaptureError.videoWriterFailed(nil) }
        writer.add(input)
        guard writer.startWriting() else { throw CaptureError.videoWriterFailed(writer.error) }
        self.writer = writer
        self.input = input

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        self.stream = stream
        try await stream.startCapture()
        captureLog.notice("video.start app=\(self.bundleID, privacy: .public) \(w, privacy: .public)x\(h, privacy: .public)")
    }

    /// Stop capture and finalize the file. Returns the URL only if a valid (non-empty) video was written;
    /// otherwise removes the stub and returns nil so the caller treats the meeting as audio-only.
    func stop() async -> URL? {
        try? await stream?.stopCapture()
        stream = nil
        lock.lock(); let started = sessionStarted; let frames = framesAppended; lock.unlock()
        input?.markAsFinished()
        guard started, frames > 0 else {
            writer?.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            captureLog.notice("video.stop produced no frames — skipping video")
            return nil
        }
        await writer?.finishWriting()
        let ok = writer?.status == .completed
        captureLog.notice("video.stop frames=\(frames, privacy: .public) ok=\(ok, privacy: .public)")
        if ok { return outputURL }
        try? FileManager.default.removeItem(at: outputURL)
        return nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        // Only append "complete" frames — skip the idle/blank deltas SCK emits when nothing on screen changed.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[SCStreamFrameInfo.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete else { return }
        guard let writer, let input, writer.status == .writing else { return }

        lock.lock()
        if !sessionStarted {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            sessionStarted = true
        }
        lock.unlock()
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
            lock.lock(); framesAppended += 1; lock.unlock()
        }
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
