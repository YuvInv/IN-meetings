import XCTest
@testable import INMeetingsCore

final class TranscriptEditorTests: XCTestCase {
    private func makeTranscript(_ utterances: [[String: Any]], language: String = "he") throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("te-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json: [String: Any] = ["meeting_id": "m1", "language": language, "speakers": [], "utterances": utterances]
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("transcript.json"))
        return dir
    }

    private func utterances(_ dir: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: dir.appendingPathComponent("transcript.json"))
        return (try JSONSerialization.jsonObject(with: data) as! [String: Any])["utterances"] as! [[String: Any]]
    }

    func testSetUtteranceTextEditsRightOneAndPreservesOthers() throws {
        let dir = try makeTranscript([
            ["text": "hello", "start": 0.0, "end": 1.0, "speaker_id": "Me"],
            ["text": "world", "start": 1.0, "end": 2.0, "speaker_id": "Them"],
        ])
        try TranscriptEditor.setUtteranceText("HELLO", at: 0, in: dir)
        let us = try utterances(dir)
        XCTAssertEqual(us[0]["text"] as? String, "HELLO")
        XCTAssertEqual(us[1]["text"] as? String, "world")          // sibling untouched
        XCTAssertEqual(us[0]["speaker_id"] as? String, "Me")       // other fields preserved
        XCTAssertEqual(us[0]["start"] as? Double, 0.0)
    }

    func testSetUtteranceTextThrowsOnBadIndex() throws {
        let dir = try makeTranscript([["text": "a", "start": 0.0, "end": 1.0, "speaker_id": "Me"]])
        XCTAssertThrowsError(try TranscriptEditor.setUtteranceText("x", at: 5, in: dir))
    }

    func testFindAndReplaceAcrossUtterancesCaseInsensitive() throws {
        let dir = try makeTranscript([
            ["text": "anthropic is great", "start": 0.0, "end": 1.0, "speaker_id": "Me"],
            ["text": "I like Anthropic", "start": 1.0, "end": 2.0, "speaker_id": "Them"],
        ])
        let (_, count) = try TranscriptEditor.findAndReplace(find: "anthropic", replaceWith: "Anthropic",
                                                             caseSensitive: false, in: dir)
        XCTAssertEqual(count, 2)
        let us = try utterances(dir)
        XCTAssertEqual(us[0]["text"] as? String, "Anthropic is great")
        XCTAssertEqual(us[1]["text"] as? String, "I like Anthropic")
    }

    func testFindAndReplaceCaseSensitiveOnlyMatchesExact() throws {
        let dir = try makeTranscript([
            ["text": "anthropic and Anthropic", "start": 0.0, "end": 1.0, "speaker_id": "Me"],
        ])
        let (_, count) = try TranscriptEditor.findAndReplace(find: "Anthropic", replaceWith: "ANTHROPIC",
                                                             caseSensitive: true, in: dir)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(try utterances(dir)[0]["text"] as? String, "anthropic and ANTHROPIC")
    }

    func testFindAndReplaceHebrew() throws {
        let dir = try makeTranscript([["text": "אנתרופיק מצוין", "start": 0.0, "end": 1.0, "speaker_id": "Me"]])
        let (_, count) = try TranscriptEditor.findAndReplace(find: "אנתרופיק", replaceWith: "Anthropic",
                                                             caseSensitive: false, in: dir)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(try utterances(dir)[0]["text"] as? String, "Anthropic מצוין")
    }

    func testFindAndReplaceNoMatchReturnsZero() throws {
        let dir = try makeTranscript([["text": "hello", "start": 0.0, "end": 1.0, "speaker_id": "Me"]])
        let (_, count) = try TranscriptEditor.findAndReplace(find: "zzz", replaceWith: "x",
                                                             caseSensitive: false, in: dir)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(try utterances(dir)[0]["text"] as? String, "hello")
    }
}
