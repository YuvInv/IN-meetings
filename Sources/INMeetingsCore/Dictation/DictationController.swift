import Foundation
import Observation
import os

private let controllerLog = Logger(subsystem: "com.in-venture.in-meetings", category: "dictation")

/// Drives the global-hotkey dictation flow (A6): a hotkey toggles a mic clip → on-device transcription →
/// paste at the cursor. **Opt-in** — the two hotkeys are registered only while `DictationSettings.enabled`.
///
/// State machine: `idle → recording(lang) → transcribing → done/failed`. Pressing the same dictation
/// hotkey again (or calling `stop()` from a Stop affordance / Esc) while recording stops the clip and
/// transcribes it; a second *different*-language press while already recording is ignored (one clip at a
/// time). `done`/`failed` are transient and settle back to `idle`.
///
/// Toggle (not hold-to-talk) because Carbon `RegisterEventHotKey` reliably delivers key-PRESS only
/// (decision 2). The recorder + transcriber + paste are injected as seams so the FSM is unit-testable
/// without a real mic / `whisper-cli` / `CGEvent` (the live path uses `MicRecorder` + `WhisperCliTranscriber`
/// + `CursorPaste`).
@MainActor
@Observable
public final class DictationController {
    public enum State: Equatable, Sendable {
        case idle
        case recording(language: String)
        case transcribing
        case done(text: String)
        case failed(message: String)
    }

    /// A mic clip recorder seam (so tests don't touch the real mic; `MicRecorder` is internal). `start`
    /// throws if the engine can't start; `peakDB` feeds the overlay's live level. Main-actor-isolated to
    /// match the controller (the live `MicRecorder` is too).
    @MainActor
    public protocol Recording: AnyObject {
        func start() throws
        func stop()
        var peakDB: Float { get }
    }

    /// Transcribes a finished clip. Default is `WhisperCliTranscriber`; tests inject a fake.
    public protocol Transcribing: Sendable {
        func transcribe(wav: URL, language: String) async -> Result<String, Error>
    }

    public private(set) var state: State = .idle

    /// Live mic level (dBFS) while `recording`, else the silence floor — drives the overlay meter.
    public var level: Float { recorder?.peakDB ?? -120 }

    /// True whenever the overlay should be shown (anything but the settled `idle`).
    public var isActive: Bool { state != .idle }

    private let settings: DictationSettings
    private let transcriber: any Transcribing
    /// Builds a fresh clip recorder writing to `clipURL` (a new instance per clip; the WAV is overwritten).
    private let makeRecorder: @MainActor (URL) -> Recording
    /// Performs the paste (default: `CursorPaste.setClipboardAndPaste`); injected so tests assert it fires.
    private let paste: @MainActor (String) -> Void
    /// Returns whether paste will actually land (the AX grant); injected so tests/UI can check + nudge.
    private let accessibilityTrusted: @MainActor () -> Bool

    private var heHotKey: GlobalHotKey?
    private var enHotKey: GlobalHotKey?
    private var recorder: Recording?
    private var clipURL: URL?
    /// Bumped each time recording starts so a stale transcribe Task (from a superseded clip) is ignored.
    private var generation = 0

    /// - Parameters:
    ///   - makeRecorder: clip-recorder factory; defaults to a mic-only `MicRecorder`. Override in tests.
    ///   - paste: default `CursorPaste.setClipboardAndPaste`. Override in tests.
    ///   - accessibilityTrusted: default `Permissions.isAccessibilityTrusted`. Override in tests.
    public init(settings: DictationSettings,
                transcriber: any Transcribing,
                makeRecorder: (@MainActor (URL) -> Recording)? = nil,
                paste: (@MainActor (String) -> Void)? = nil,
                accessibilityTrusted: (@MainActor () -> Bool)? = nil) {
        self.settings = settings
        self.transcriber = transcriber
        self.makeRecorder = makeRecorder ?? { url in MicRecorderClip(outputURL: url) }
        self.paste = paste ?? { CursorPaste.setClipboardAndPaste($0) }
        self.accessibilityTrusted = accessibilityTrusted ?? { Permissions.isAccessibilityTrusted() }
    }

    // MARK: - Lifecycle

    /// Register the two hotkeys iff dictation is enabled; a no-op when disabled (keeps Esc/letters free and
    /// avoids any AX nag for users who never turned it on). Idempotent — call again after toggling `enabled`.
    public func refreshHotKeys() {
        guard settings.enabled else {
            heHotKey = nil
            enHotKey = nil
            return
        }
        if heHotKey == nil {
            heHotKey = GlobalHotKey(keyCode: settings.heKeyCode, modifiers: settings.heModifiers) {
                [weak self] in self?.toggle(language: "he")
            }
        }
        if enHotKey == nil {
            enHotKey = GlobalHotKey(keyCode: settings.enKeyCode, modifiers: settings.enModifiers) {
                [weak self] in self?.toggle(language: "en")
            }
        }
    }

    /// Tear the hotkeys down (e.g. the user disabled dictation in Settings).
    public func disableHotKeys() {
        heHotKey = nil
        enHotKey = nil
    }

    // MARK: - Flow

    /// The hotkey action: start a clip if idle, or stop+transcribe the in-flight clip (toggle, decision 2).
    /// A press in a non-idle, non-recording state (transcribing) is ignored — one clip at a time.
    public func toggle(language: String) {
        switch state {
        case .idle, .done, .failed:
            startRecording(language: language)
        case .recording:
            stop()
        case .transcribing:
            break   // busy; ignore until it settles
        }
    }

    /// Stop the current clip and kick off transcription (the Stop affordance / Esc / a second hotkey press).
    /// No-op unless we're recording.
    public func stop() {
        guard case .recording(let language) = state else { return }
        recorder?.stop()
        guard let clipURL else {
            settle(.failed(message: "Dictation clip wasn't written."))
            return
        }
        state = .transcribing
        let gen = generation
        let transcriber = transcriber
        Task { [weak self] in
            let result = await transcriber.transcribe(wav: clipURL, language: language)
            guard let self else { return }
            self.finishTranscription(result, generation: gen)
        }
    }

    private func startRecording(language: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("in-meetings-dictation-clip.wav")
        try? FileManager.default.removeItem(at: url)
        let rec = makeRecorder(url)
        do {
            try rec.start()
        } catch {
            controllerLog.error("dictation.record start failed: \(error.localizedDescription, privacy: .public)")
            settle(.failed(message: "Couldn't start the microphone. Check the Microphone permission."))
            return
        }
        recorder = rec
        clipURL = url
        generation += 1
        state = .recording(language: language)
        controllerLog.notice("dictation.record start lang=\(language, privacy: .public)")
    }

    private func finishTranscription(_ result: Result<String, Error>, generation gen: Int) {
        guard gen == generation else { return }   // a newer clip superseded this one
        recorder = nil
        switch result {
        case .success(let text):
            controllerLog.notice("dictation.transcribe ok chars=\(text.count, privacy: .public)")
            paste(text)
            settle(.done(text: text))
        case .failure(let error):
            controllerLog.error("dictation.transcribe failed: \(error.localizedDescription, privacy: .public)")
            settle(.failed(message: Self.message(for: error)))
        }
    }

    /// Show a terminal state briefly (so the overlay can flash "Pasted" / an error), then fall back to idle.
    private func settle(_ terminal: State) {
        state = terminal
        let gen = generation
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, self.generation == gen, self.state == terminal else { return }
            self.state = .idle
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case WhisperCliTranscriber.TranscribeError.whisperNotFound:
            return "whisper-cli isn't installed (brew install whisper-cpp)."
        case WhisperCliTranscriber.TranscribeError.noOutput:
            return "No speech detected."
        default:
            return "Transcription failed."
        }
    }
}

/// Live `Recording` backed by the internal `MicRecorder` (mic-only clip). Kept private so `MicRecorder`
/// stays internal while `DictationController.Recording` is the public seam tests substitute.
@MainActor
private final class MicRecorderClip: DictationController.Recording {
    private let recorder: MicRecorder
    init(outputURL: URL) { self.recorder = MicRecorder(outputURL: outputURL) }
    func start() throws { try recorder.start() }
    func stop() { recorder.stop() }
    var peakDB: Float { recorder.peakDB }
}
