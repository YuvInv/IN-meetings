import Foundation

/// Orchestrates importing an external recording into a new meeting folder, then handing it to the
/// pipeline. Seams are injected so it's unit-testable without AVFoundation or spawning Python; the app
/// wires the real `AudioImporter` / `CalendarContext.writePinnedInput` / `JobBridge.enqueueImport`.
public struct MeetingImporter {
    /// Decode + normalize `input` → 16 kHz mono WAV at `output`.
    public var convert: (_ input: URL, _ output: URL) async throws -> Void
    /// Write `context.input.json` pinned to the chosen event (event path only).
    public var writePinnedContext: (_ dir: URL, _ event: CalendarEvent, _ start: Date, _ end: Date) -> Void
    /// Kick the pipeline on the prepared folder.
    public var enqueue: (_ dir: URL, _ audioFilename: String, _ start: Date, _ end: Date) -> Void

    public init(
        convert: @escaping (URL, URL) async throws -> Void = AudioImporter.convertToWav16kMono,
        writePinnedContext: @escaping (URL, CalendarEvent, Date, Date) -> Void,
        enqueue: @escaping (URL, String, Date, Date) -> Void
    ) {
        self.convert = convert
        self.writePinnedContext = writePinnedContext
        self.enqueue = enqueue
    }

    /// Import `fileURL` as a new meeting. When `event` is non-nil the meeting is bound to it (context +
    /// attendees); `start`/`end` should be the event's window (or `Date()` for a no-event import). Returns
    /// the new meeting id (its folder name). Cleans up the folder if anything fails before enqueue.
    @discardableResult
    public func importRecording(from fileURL: URL, event: CalendarEvent?,
                                start: Date, end: Date) async throws -> String {
        let dir = uniqueMeetingDirectory(preferredStart: start)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let wav = dir.appendingPathComponent("audio.wav")
            try await convert(fileURL, wav)
            if let event { writePinnedContext(dir, event, start, end) }
            enqueue(dir, "audio.wav", start, end)
            return dir.lastPathComponent
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
    }

    /// A timestamped folder under the recordings root; bumps by a second if one already exists so two
    /// imports of the same event don't collide.
    private func uniqueMeetingDirectory(preferredStart: Date) -> URL {
        var when = preferredStart
        var dir = RecordingsStore.newMeetingDirectory(now: when)
        while FileManager.default.fileExists(atPath: dir.path) {
            when = when.addingTimeInterval(1)
            dir = RecordingsStore.newMeetingDirectory(now: when)
        }
        return dir
    }
}
