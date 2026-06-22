import XCTest
import Foundation
@testable import INMeetingsCore

final class CalendarPinnedInputTests: XCTestCase {
    func testPinnedPayloadHasSingleCandidateWithAttendees() throws {
        let event = CalendarEvent(
            id: "evt123", summary: "Acme intro",
            start: .init(dateTime: "2026-06-22T10:00:00Z", date: nil),
            end: .init(dateTime: "2026-06-22T10:30:00Z", date: nil),
            hangoutLink: "https://meet.google.com/x",
            attendees: [.init(email: "dana@acme.com", displayName: "Dana Cohen", organizer: false)])
        let iso = ISO8601DateFormatter()
        let start = iso.date(from: "2026-06-22T10:00:00Z")!
        let end = iso.date(from: "2026-06-22T10:30:00Z")!

        let payload = CalendarContext.inputPayload(
            internalDomain: "in-venture.com", candidates: [event],
            captureSourceApp: nil, startedAt: start, endedAt: end)

        let candidates = try XCTUnwrap(payload["candidates"] as? [[String: Any]])
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0]["id"] as? String, "evt123")
        let attendees = try XCTUnwrap(candidates[0]["attendees"] as? [[String: Any]])
        XCTAssertEqual(attendees.first?["email"] as? String, "dana@acme.com")
        XCTAssertEqual(payload["status"] as? String, "ok")
    }
}
