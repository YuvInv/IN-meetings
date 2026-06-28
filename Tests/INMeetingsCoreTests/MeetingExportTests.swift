import XCTest
@testable import INMeetingsCore

/// PR 4: the Markdown / HTML export builders. Pure string output, so asserted directly.
final class MeetingExportTests: XCTestCase {
    private func transcript(_ json: String) throws -> TranscriptPackage {
        try PackageReader.makeDecoder().decode(TranscriptPackage.self, from: Data(json.utf8))
    }
    private func metadata(_ json: String) throws -> MeetingMetadata {
        try PackageReader.makeDecoder().decode(MeetingMetadata.self, from: Data(json.utf8))
    }

    private let englishTranscript = """
    {"meeting_id":"m1","language":"en","speakers":[
        {"id":"Me","side":"internal","name":"Dana"},
        {"id":"Speaker 1","side":"external"}],
     "utterances":[
        {"text":"Hello there","start":5.0,"end":7.0,"speaker_id":"Me"},
        {"text":"Hi Dana","start":3725.0,"end":3728.0,"speaker_id":"Speaker 1"}]}
    """
    private let meta = """
    {"schema_version":"1.0",
     "meeting":{"title":"Intro call","start":"2026-06-25T14:30:00Z","end":"2026-06-25T15:00:00Z","type":"call"},
     "attendees":[{"name":"Dana Levi","email":"dana@x.com","side":"internal"},{"name":"Sam","side":"external"}],
     "company":{"name":"Acme","matched":true},
     "recording":{"tracks":["mic","system"],"video":false},
     "transcription":{"engine":"whisper.cpp","model_revision":"x","language":"en","biased":false}}
    """

    func testMarkdownIncludesHeaderTimestampsSpeakersAndSummary() throws {
        let md = MeetingExport.markdown(
            transcript: try transcript(englishTranscript), metadata: try metadata(meta),
            company: "Acme", fallbackTitle: "Intro call", durationSeconds: 1800,
            summary: "Key points: raised a Series A.")
        XCTAssertTrue(md.contains("# Acme"))
        XCTAssertTrue(md.contains("**Title:** Intro call"))
        XCTAssertTrue(md.contains("**Date:**"))
        XCTAssertTrue(md.contains("2026"))                      // date rendered (tz-agnostic assertion)
        XCTAssertTrue(md.contains("**Type:** Call"))
        XCTAssertTrue(md.contains("Dana Levi (dana@x.com)"))    // attendees
        XCTAssertTrue(md.contains("## Summary"))
        XCTAssertTrue(md.contains("Key points: raised a Series A."))
        XCTAssertTrue(md.contains("## Transcript"))
        // speaker label + [HH:MM:SS] timestamp
        XCTAssertTrue(md.contains("[00:00:05] **Dana:** Hello there"))
        XCTAssertTrue(md.contains("[01:02:05] **Speaker 1:** Hi Dana"))   // assigned name vs raw id
    }

    func testMarkdownOmitsSummarySectionWhenAbsent() throws {
        let md = MeetingExport.markdown(
            transcript: try transcript(englishTranscript), metadata: try metadata(meta),
            company: "Acme", fallbackTitle: nil, durationSeconds: 1800, summary: nil)
        XCTAssertFalse(md.contains("## Summary"))
        XCTAssertTrue(md.contains("## Transcript"))
    }

    func testHtmlIsRtlForHebrewLtrOtherwise() throws {
        let en = MeetingExport.html(transcript: try transcript(englishTranscript), metadata: nil,
                                    company: "Acme", fallbackTitle: nil, durationSeconds: nil, summary: nil)
        XCTAssertTrue(en.contains("dir=\"ltr\""))

        let hebrewJSON = """
        {"language":"he","speakers":[{"id":"Me","side":"internal"}],
         "utterances":[{"text":"שלום","start":0.0,"end":1.0,"speaker_id":"Me"}]}
        """
        let he = MeetingExport.html(transcript: try transcript(hebrewJSON), metadata: nil,
                                    company: nil, fallbackTitle: "פגישה", durationSeconds: nil, summary: nil)
        XCTAssertTrue(he.contains("dir=\"rtl\""))
        XCTAssertTrue(he.contains("שלום"))
    }

    func testFilenameStemSanitizesIllegalCharacters() {
        let stem = MeetingExport.filenameStem(company: "Acme/Co:Inc", title: "x", startedAtISO: "2026-06-25T14:30:00Z")
        XCTAssertFalse(stem.contains("/"))
        XCTAssertFalse(stem.contains(":"))
        XCTAssertTrue(stem.contains("2026-06-25"))
    }

    func testClockFormatsHoursMinutesSeconds() {
        XCTAssertEqual(MeetingExport.clock(5), "00:00:05")
        XCTAssertEqual(MeetingExport.clock(3725), "01:02:05")
    }
}
