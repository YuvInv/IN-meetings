import XCTest
@testable import INMeetingsCore

private enum TranscriptStub {
    /// A minimal utterance spanning `[start, end)` — only the timing matters for these tests.
    static func u(_ start: Double, _ end: Double) -> TranscriptPackage.Utterance {
        TranscriptPackage.Utterance(text: "", start: start, end: end, speakerId: "s1", confidence: nil)
    }
}

final class MeetingBucketingTests: XCTestCase {
    private func rec(_ id: String, company: String?, title: String?, start: String,
                     matched: Bool = true, status: String = "done") -> MeetingRecord {
        MeetingRecord(id: id, company: company, title: title, type: "call", startedAt: start,
                      endedAt: start, durationSeconds: 60, status: status, speakerCount: 2,
                      diarized: true, biased: true, modelRevision: "r", captureSourceApp: nil,
                      folderPath: "/tmp/\(id)", consentStatus: nil, driveFolderId: nil, syncState: "synced")
    }
    func testFilterMatchesCompanyTitleAndId() {
        let recs = [rec("a", company: "Prelligence", title: "Sync", start: "2026-06-14T10:00:00Z"),
                    rec("b", company: "Algolion", title: "Pitch", start: "2026-06-13T10:00:00Z")]
        XCTAssertEqual(filterMeetings(recs, search: "prell").map(\.id), ["a"])
        XCTAssertEqual(filterMeetings(recs, search: "pitch").map(\.id), ["b"])
        XCTAssertEqual(filterMeetings(recs, search: "").map(\.id), ["a", "b"])
    }
    func testNeedsLinkingAndProcessing() {
        let recs = [rec("a", company: nil, title: nil, start: "2026-06-14T10:00:00Z", matched: false),
                    rec("b", company: "X", title: "t", start: "2026-06-14T10:00:00Z", status: "running")]
        XCTAssertEqual(needsLinking(recs).map(\.id), ["a"])        // no company
        XCTAssertEqual(processing(recs).map(\.id), ["b"])          // not done/synced
    }
    func testActiveUtterance() {
        let us = [TranscriptStub.u(0, 2), TranscriptStub.u(2, 5), TranscriptStub.u(5, 9)]
        XCTAssertEqual(activeUtteranceIndex(in: us, at: 3.0), 1)
        XCTAssertEqual(activeUtteranceIndex(in: us, at: 9.5), nil)
    }
}
