import XCTest
@testable import INMeetingsCore

/// The dictation transcriber. The live `whisper-cli` spawn is live-verify only; here we test the pure
/// arg/parse helpers + the orchestration (resolve → run → read `<base>.txt`) via a stubbed process.
final class WhisperCliTranscriberTests: XCTestCase {
    private let model = URL(fileURLWithPath: "/models/ivrit.ggml.bin")

    // MARK: - Pure helpers

    func testArgumentsBuildExpectedFlags() {
        let args = WhisperCliTranscriber.arguments(
            whisperCli: URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            model: model,
            wav: URL(fileURLWithPath: "/tmp/clip.wav"),
            outBase: URL(fileURLWithPath: "/tmp/clip"),
            language: "he")
        XCTAssertEqual(args.first, "/opt/homebrew/bin/whisper-cli")
        // -m <model>
        XCTAssertEqual(args[args.firstIndex(of: "-m")! + 1], "/models/ivrit.ggml.bin")
        // -f <wav>
        XCTAssertEqual(args[args.firstIndex(of: "-f")! + 1], "/tmp/clip.wav")
        // -l <lang>
        XCTAssertEqual(args[args.firstIndex(of: "-l")! + 1], "he")
        // text output, not JSON
        XCTAssertTrue(args.contains("-otxt"))
        XCTAssertFalse(args.contains("-oj"))
        // -of <outBase>
        XCTAssertEqual(args[args.firstIndex(of: "-of")! + 1], "/tmp/clip")
        // dictation path runs no VAD
        XCTAssertFalse(args.contains("--vad"))
    }

    func testResolveWhisperCliFindsExecutableOnPath() throws {
        let bin = URL(filePath: NSTemporaryDirectory()).appending(path: "wbin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bin) }
        let exe = bin.appendingPathComponent("whisper-cli")
        FileManager.default.createFile(atPath: exe.path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        let found = WhisperCliTranscriber.resolveWhisperCliURL(environment: ["PATH": bin.path])
        XCTAssertEqual(found?.lastPathComponent, "whisper-cli")
    }

    func testParseTranscriptTrimsAndRejectsBlank() throws {
        let txt = URL(filePath: NSTemporaryDirectory()).appending(path: "wt-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: txt) }
        try "  שלום עולם \n".write(to: txt, atomically: true, encoding: .utf8)
        XCTAssertEqual(WhisperCliTranscriber.parseTranscript(at: txt), "שלום עולם")

        try "   \n\n  ".write(to: txt, atomically: true, encoding: .utf8)
        XCTAssertNil(WhisperCliTranscriber.parseTranscript(at: txt))

        let missing = URL(filePath: NSTemporaryDirectory()).appending(path: "nope-\(UUID().uuidString).txt")
        XCTAssertNil(WhisperCliTranscriber.parseTranscript(at: missing))
    }

    // MARK: - Orchestration (stubbed process)

    func testTranscribeSuccessReadsTrimmedText() async throws {
        let wav = URL(filePath: NSTemporaryDirectory()).appending(path: "clip-\(UUID().uuidString).wav")
        let transcriber = WhisperCliTranscriber(
            model: model,
            whisperCliURL: URL(fileURLWithPath: "/usr/bin/true"),   // bypass PATH resolution
            runProcessOverride: { _, outBase in
                // The seam plays whisper.cpp: write the `<base>.txt` the transcriber will read.
                try? "  hello there  \n".write(to: outBase.appendingPathExtension("txt"),
                                               atomically: true, encoding: .utf8)
                return .init(exitCode: 0, stdout: "")
            })
        defer { try? FileManager.default.removeItem(at: wav.deletingPathExtension().appendingPathExtension("txt")) }

        let result = await transcriber.transcribe(wav: wav, language: "en")
        switch result {
        case .success(let text): XCTAssertEqual(text, "hello there")
        case .failure(let error): XCTFail("expected success, got \(error)")
        }
    }

    func testTranscribeFailsOnNonZeroExit() async throws {
        let wav = URL(filePath: NSTemporaryDirectory()).appending(path: "clip-\(UUID().uuidString).wav")
        let transcriber = WhisperCliTranscriber(
            model: model,
            whisperCliURL: URL(fileURLWithPath: "/usr/bin/true"),
            runProcessOverride: { _, _ in .init(exitCode: 1, stdout: "boom") })

        let result = await transcriber.transcribe(wav: wav, language: "he")
        guard case .failure(let error) = result,
              case WhisperCliTranscriber.TranscribeError.processFailed(let code, _) = error else {
            return XCTFail("expected processFailed, got \(result)")
        }
        XCTAssertEqual(code, 1)
    }

    func testTranscribeFailsWhenNoOutputWritten() async throws {
        let wav = URL(filePath: NSTemporaryDirectory()).appending(path: "clip-\(UUID().uuidString).wav")
        let transcriber = WhisperCliTranscriber(
            model: model,
            whisperCliURL: URL(fileURLWithPath: "/usr/bin/true"),
            runProcessOverride: { _, _ in .init(exitCode: 0, stdout: "") })   // exit 0 but no .txt written

        let result = await transcriber.transcribe(wav: wav, language: "he")
        guard case .failure(let error) = result,
              case WhisperCliTranscriber.TranscribeError.noOutput = error else {
            return XCTFail("expected noOutput, got \(result)")
        }
    }
}
