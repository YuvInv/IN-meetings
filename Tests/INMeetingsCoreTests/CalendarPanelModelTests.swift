import XCTest
import Foundation
@testable import INMeetingsCore

private final class FakeCalendar: CalendarEventsProviding, @unchecked Sendable {
    var isConnected = true
    var callCount = 0
    var byDayKey: (Date) -> [CalendarEvent] = { _ in [] }
    func fetchEvents(timeMin: Date, timeMax: Date) async throws -> [CalendarEvent] {
        callCount += 1
        return byDayKey(timeMin)
    }
}

@MainActor
final class CalendarPanelModelTests: XCTestCase {
    private func event(_ id: String) -> CalendarEvent {
        CalendarEvent(id: id, summary: id, start: .init(dateTime: "2026-06-22T10:00:00Z", date: nil),
                      end: .init(dateTime: "2026-06-22T10:30:00Z", date: nil), hangoutLink: nil, attendees: nil)
    }

    func testLoadsSelectedDayThenCachesIt() async {
        let cal = FakeCalendar()
        cal.byDayKey = { _ in [self.event("a")] }
        let model = CalendarPanelModel(calendar: cal, recordedIds: { [] },
                                       today: ISO8601DateFormatter().date(from: "2026-06-22T08:00:00Z")!)
        await model.load()
        if case .loaded(let evs) = model.state { XCTAssertEqual(evs.map(\.id), ["a"]) }
        else { XCTFail("expected loaded") }
        await model.load()                       // second load → cache hit, no extra fetch
        XCTAssertEqual(cal.callCount, 1)
        await model.load(force: true)            // refresh → re-fetch
        XCTAssertEqual(cal.callCount, 2)
    }

    func testPagingChangesDayAndFetches() async {
        let cal = FakeCalendar()
        let model = CalendarPanelModel(calendar: cal, recordedIds: { [] },
                                       today: ISO8601DateFormatter().date(from: "2026-06-22T08:00:00Z")!)
        let day0 = model.selectedDay
        await model.load()
        await model.step(days: -1)               // go to older day
        XCTAssertEqual(model.selectedDay, Calendar.current.date(byAdding: .day, value: -1, to: day0))
        XCTAssertEqual(cal.callCount, 2)
    }

    func testErrorStateOnThrow() async {
        struct Boom: Error {}
        final class Throwing: CalendarEventsProviding, @unchecked Sendable {
            var isConnected = true
            func fetchEvents(timeMin: Date, timeMax: Date) async throws -> [CalendarEvent] { throw Boom() }
        }
        let model = CalendarPanelModel(calendar: Throwing(), recordedIds: { [] }, today: Date())
        await model.load()
        if case .error = model.state {} else { XCTFail("expected error") }
    }

    func testIsRecordedReflectsRecordedIds() {
        let model = CalendarPanelModel(calendar: FakeCalendar(), recordedIds: { ["x"] }, today: Date())
        XCTAssertTrue(model.isRecorded(event("x")))
        XCTAssertFalse(model.isRecorded(event("y")))
    }
}
