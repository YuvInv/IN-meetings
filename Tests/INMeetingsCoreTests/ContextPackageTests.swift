import XCTest
@testable import INMeetingsCore

/// The cross-language contract: Swift must decode exactly what the Python pipeline writes. Both sides
/// test against the one golden fixture in `schema/fixtures/golden-package/` (ADR-005).
final class ContextPackageTests: XCTestCase {
    /// The repo's golden fixture, reached relative to this test file (Tests/INMeetingsCoreTests/…).
    private var fixture: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // INMeetingsCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appending(path: "schema/fixtures/golden-package")
    }

    func testDecodesGoldenTranscript() throws {
        let t = try PackageReader.transcript(in: fixture)
        XCTAssertEqual(t.language, "he")
        XCTAssertEqual(t.engine, "whisper.cpp")
        XCTAssertEqual(t.modelRevision, "ivrit-large-v3-turbo")
        XCTAssertEqual(t.biased, true)
        XCTAssertEqual(t.speakers.count, 2)
        XCTAssertEqual(t.utterances.first?.speakerId, "Me")
        XCTAssertEqual(t.utterances.first?.start, 0.0)
        XCTAssertEqual(t.utterances.first?.confidence, 0.94)

        // every utterance's speaker_id references a row in the speakers table
        let ids = Set(t.speakers.map(\.id))
        XCTAssertTrue(t.utterances.allSatisfy { ids.contains($0.speakerId) })
    }

    func testDecodesGoldenMetadata() throws {
        let m = try PackageReader.metadata(in: fixture)
        XCTAssertEqual(m.schemaVersion, "1.0")
        XCTAssertEqual(m.meeting.type, "call")
        XCTAssertEqual(m.meeting.title, "Prelligence — Series A intro")
        XCTAssertEqual(m.company?.name, "Prelligence")
        XCTAssertEqual(m.company?.matched, true)
        XCTAssertEqual(m.company?.sevantaDealId, "deal_4421")
        XCTAssertEqual(m.recording.tracks, ["mic", "system"])
        XCTAssertEqual(m.recording.video, false)
        XCTAssertEqual(m.recording.captureSourceApp, "us.zoom.xos")
        XCTAssertEqual(m.transcription.modelRevision, "ivrit-large-v3-turbo")
        XCTAssertEqual(m.attendees?.count, 2)
    }
}
