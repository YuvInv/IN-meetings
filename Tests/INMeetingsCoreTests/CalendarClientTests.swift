import XCTest
@testable import INMeetingsCore

final class CalendarClientTests: XCTestCase {
    func testOAuthScopesIncludeCalendarReadonly() {
        XCTAssertTrue(DriveConfig.oauth.scopes.contains("https://www.googleapis.com/auth/calendar.events.readonly"))
        XCTAssertTrue(DriveConfig.oauth.scopes.contains("https://www.googleapis.com/auth/drive"))
    }

    func testEventsURLBuildsWindowedPrimaryQuery() throws {
        let min = Date(timeIntervalSince1970: 1_780_000_000)
        let max = Date(timeIntervalSince1970: 1_780_003_600)
        let url = CalendarClient.eventsURL(timeMin: min, timeMax: max)
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertTrue(url.path.hasSuffix("/calendars/primary/events"))
        let q = Dictionary(uniqueKeysWithValues: comps.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["singleEvents"], "true")
        XCTAssertEqual(q["orderBy"], "startTime")
        XCTAssertNotNil(q["timeMin"])
        XCTAssertNotNil(q["timeMax"])
        XCTAssertTrue((q["fields"] ?? "").contains("attendees"))
    }

    func testDecodesEventsResponse() throws {
        let json = """
        {"items":[{"id":"e1","summary":"Prelligence <> IN Venture",
          "start":{"dateTime":"2026-06-14T10:00:00Z"},"end":{"dateTime":"2026-06-14T10:30:00Z"},
          "hangoutLink":"https://meet.google.com/x",
          "attendees":[{"email":"founder@prelligence.com","displayName":"Founder","organizer":false}]}]}
        """.data(using: .utf8)!
        let events = try CalendarClient.decodeEvents(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].id, "e1")
        XCTAssertEqual(events[0].start.dateTime, "2026-06-14T10:00:00Z")
        XCTAssertEqual(events[0].attendees?.first?.email, "founder@prelligence.com")
    }

    func testDecodesEmptyBodyWithoutItemsAsNoEvents() throws {
        // Calendar can return a body with no `items` key for an empty day — decode to [] (not throw),
        // so the day-agenda panel shows "No events" instead of an error state.
        let json = #"{"kind":"calendar#events"}"#.data(using: .utf8)!
        XCTAssertEqual(try CalendarClient.decodeEvents(json).count, 0)
    }
}
