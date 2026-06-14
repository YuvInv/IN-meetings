import XCTest
@testable import INMeetingsCore

final class CalendarContextTests: XCTestCase {
    func testDomainOfEmail() {
        XCTAssertEqual(CalendarContext.domain(ofEmail: "Yuval@IN-Venture.com"), "in-venture.com")
        XCTAssertEqual(CalendarContext.domain(ofEmail: "broken"), "")
    }

    func testInputPayloadFlattensEventsAndHints() throws {
        let event = CalendarEvent(
            id: "e1", summary: "Prelligence <> IN Venture",
            start: .init(dateTime: "2026-06-14T10:00:00Z", date: nil),
            end: .init(dateTime: "2026-06-14T10:30:00Z", date: nil),
            hangoutLink: "https://meet.google.com/x",
            attendees: [.init(email: "founder@prelligence.com", displayName: "Founder", organizer: false)])
        let payload = CalendarContext.inputPayload(
            internalDomain: "in-venture.com", candidates: [event],
            captureSourceApp: "Chrome",
            startedAt: Date(timeIntervalSince1970: 1_780_000_000),
            endedAt: Date(timeIntervalSince1970: 1_780_001_800))

        XCTAssertEqual(payload["internal_domain"] as? String, "in-venture.com")
        let hints = payload["hints"] as! [String: Any]
        XCTAssertEqual(hints["capture_source_app"] as? String, "Chrome")
        let cands = payload["candidates"] as! [[String: Any]]
        XCTAssertEqual(cands.first?["id"] as? String, "e1")
        XCTAssertEqual(cands.first?["start"] as? String, "2026-06-14T10:00:00Z")
        XCTAssertEqual(cands.first?["has_link"] as? Bool, true)
        let atts = cands.first?["attendees"] as! [[String: Any]]
        XCTAssertEqual(atts.first?["email"] as? String, "founder@prelligence.com")
    }
}
