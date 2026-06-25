import XCTest
@testable import INMeetingsCore

@MainActor
final class DictationControllerTests: XCTestCase {
    private func freshSettings() -> DictationSettings {
        DictationSettings(defaults: UserDefaults(suiteName: "dictctl-\(UUID().uuidString)")!)
    }

    // MARK: - Test seams

    /// A fake clip recorder — never touches the real mic.
    private final class FakeRecorder: DictationController.Recording {
        var started = false
        var stopped = false
        let startError: Error?
        init(startError: Error? = nil) { self.startError = startError }
        func start() throws { if let startError { throw startError } ; started = true }
        func stop() { stopped = true }
        var peakDB: Float { -20 }
    }

    /// A fake transcriber returning a canned result.
    private struct FakeTranscriber: DictationController.Transcribing {
        let result: Result<String, Error>
        func transcribe(wav: URL, language: String) async -> Result<String, Error> { result }
    }

    private struct StubError: Error {}

    /// Records what was pasted (the paste seam runs on the main actor).
    private final class PasteSpy {
        var pasted: [String] = []
        func callAsFunction(_ text: String) { pasted.append(text) }
    }

    /// Spin the main actor until `predicate` holds or we time out (the transcribe + settle hop off via Task).
    private func waitUntil(_ predicate: () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Happy path

    func testHotkeyRecordsThenStopTranscribesAndPastes() async {
        let spy = PasteSpy()
        var lastRecorder: FakeRecorder?
        let controller = DictationController(
            settings: freshSettings(),
            transcriber: FakeTranscriber(result: .success("hello world")),
            makeRecorder: { _ in let r = FakeRecorder(); lastRecorder = r; return r },
            paste: { spy($0) },
            accessibilityTrusted: { true })

        controller.toggle(language: "en")   // press → start recording
        guard case .recording(let lang) = controller.state else {
            return XCTFail("expected recording, got \(controller.state)")
        }
        XCTAssertEqual(lang, "en")
        XCTAssertTrue(lastRecorder?.started ?? false)

        controller.toggle(language: "en")   // press again → stop → transcribe
        XCTAssertTrue(lastRecorder?.stopped ?? false)

        await waitUntil { if case .done = controller.state { return true }; return false }
        guard case .done(let text) = controller.state else {
            return XCTFail("expected done, got \(controller.state)")
        }
        XCTAssertEqual(text, "hello world")
        XCTAssertEqual(spy.pasted, ["hello world"])
    }

    func testStopMethodAlsoEndsRecording() async {
        let spy = PasteSpy()
        let controller = DictationController(
            settings: freshSettings(),
            transcriber: FakeTranscriber(result: .success("from stop")),
            makeRecorder: { _ in FakeRecorder() },
            paste: { spy($0) })

        controller.toggle(language: "he")
        controller.stop()                   // the Stop affordance / Esc path
        await waitUntil { if case .done = controller.state { return true }; return false }
        XCTAssertEqual(spy.pasted, ["from stop"])
    }

    // MARK: - Failure paths

    func testTranscriberFailureSetsFailedAndDoesNotPaste() async {
        let spy = PasteSpy()
        let controller = DictationController(
            settings: freshSettings(),
            transcriber: FakeTranscriber(result: .failure(StubError())),
            makeRecorder: { _ in FakeRecorder() },
            paste: { spy($0) })

        controller.toggle(language: "he")
        controller.toggle(language: "he")   // stop → transcribe (fails)
        await waitUntil { if case .failed = controller.state { return true }; return false }
        guard case .failed = controller.state else {
            return XCTFail("expected failed, got \(controller.state)")
        }
        XCTAssertTrue(spy.pasted.isEmpty, "must not paste on transcription failure")
    }

    func testRecorderStartFailureSetsFailed() async {
        let spy = PasteSpy()
        let controller = DictationController(
            settings: freshSettings(),
            transcriber: FakeTranscriber(result: .success("never")),
            makeRecorder: { _ in FakeRecorder(startError: StubError()) },
            paste: { spy($0) })

        controller.toggle(language: "he")
        guard case .failed = controller.state else {
            return XCTFail("expected failed on mic-start error, got \(controller.state)")
        }
        XCTAssertTrue(spy.pasted.isEmpty)
    }

    // MARK: - Toggle semantics

    func testSecondHotkeyWhileRecordingStopsAndTranscribes() async {
        let spy = PasteSpy()
        var recorders: [FakeRecorder] = []
        let controller = DictationController(
            settings: freshSettings(),
            transcriber: FakeTranscriber(result: .success("toggled")),
            makeRecorder: { _ in let r = FakeRecorder(); recorders.append(r); return r },
            paste: { spy($0) })

        controller.toggle(language: "en")   // start
        controller.toggle(language: "en")   // second press stops + transcribes (does NOT start a new clip)
        await waitUntil { if case .done = controller.state { return true }; return false }
        XCTAssertEqual(recorders.count, 1, "second press should stop, not start a new clip")
        XCTAssertTrue(recorders.first?.stopped ?? false)
        XCTAssertEqual(spy.pasted, ["toggled"])
    }

    func testTogglePressWhileTranscribingIsIgnored() async {
        let spy = PasteSpy()
        var recorders: [FakeRecorder] = []
        // Transcriber that blocks until released, so we can press the hotkey mid-transcription.
        let gate = Gate()
        let controller = DictationController(
            settings: freshSettings(),
            transcriber: BlockingTranscriber(gate: gate, result: .success("done")),
            makeRecorder: { _ in let r = FakeRecorder(); recorders.append(r); return r },
            paste: { spy($0) })

        controller.toggle(language: "en")   // recording
        controller.toggle(language: "en")   // stop → transcribing (blocked)
        await waitUntil { controller.state == .transcribing }
        controller.toggle(language: "en")   // press while transcribing → ignored
        XCTAssertEqual(controller.state, .transcribing)
        XCTAssertEqual(recorders.count, 1, "no new clip should start while transcribing")
        await gate.open()
        await waitUntil { if case .done = controller.state { return true }; return false }
        XCTAssertEqual(spy.pasted, ["done"])
    }

    // MARK: - Opt-in registration

    func testRefreshHotKeysIsNoOpWhenDisabled() {
        let settings = freshSettings()
        XCTAssertFalse(settings.enabled)
        let controller = DictationController(
            settings: settings, transcriber: FakeTranscriber(result: .success("x")),
            makeRecorder: { _ in FakeRecorder() })
        // Should not crash and should register nothing while disabled; toggling still works programmatically.
        controller.refreshHotKeys()
        controller.disableHotKeys()
    }
}

/// A transcriber that waits on a gate before returning — lets a test observe the `transcribing` state.
private struct BlockingTranscriber: DictationController.Transcribing {
    let gate: Gate
    let result: Result<String, Error>
    func transcribe(wav: URL, language: String) async -> Result<String, Error> {
        await gate.wait()
        return result
    }
}

/// One-shot async gate.
private actor Gate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func open() {
        opened = true
        for c in continuations { c.resume() }
        continuations.removeAll()
    }
}
