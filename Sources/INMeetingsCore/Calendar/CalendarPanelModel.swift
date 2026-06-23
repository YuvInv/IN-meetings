import Foundation
import Observation

/// Day-at-a-time agenda for the dashboard calendar panel. Holds the selected day, a per-day cache (paging
/// is instant; refresh forces a re-fetch), and which events already have a recording. Foundation-only +
/// `@Observable` so the SwiftUI panel observes it and it stays unit-testable in Core.
@MainActor
@Observable
public final class CalendarPanelModel {
    public enum DayState: Sendable {
        case loading
        case loaded([CalendarEvent])
        case error(String)
    }

    private let calendar: CalendarEventsProviding
    private let recordedIds: () -> Set<String>
    private var cache: [Date: [CalendarEvent]] = [:]

    public private(set) var selectedDay: Date
    public private(set) var state: DayState = .loading

    public init(calendar: CalendarEventsProviding, recordedIds: @escaping () -> Set<String>,
                today: Date = Date()) {
        self.calendar = calendar
        self.recordedIds = recordedIds
        self.selectedDay = Calendar.current.startOfDay(for: today)
    }

    public var isConnected: Bool { calendar.isConnected }

    /// Load the selected day. Cache hit returns instantly unless `force` (the ⟳ refresh).
    public func load(force: Bool = false) async {
        let day = selectedDay
        if !force, let cached = cache[day] { state = .loaded(cached); return }
        state = .loading
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        do {
            let events = try await calendar.fetchEvents(timeMin: start, timeMax: end)
            cache[day] = events
            if day == selectedDay { state = .loaded(events) }
        } catch {
            if day == selectedDay { state = .error(error.localizedDescription) }
        }
    }

    /// Move the agenda by `days` (−1 older, +1 newer) and load it.
    public func step(days: Int) async {
        selectedDay = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) ?? selectedDay
        await load()
    }

    /// Jump back to today and load it.
    public func goToToday(now: Date = Date()) async {
        selectedDay = Calendar.current.startOfDay(for: now)
        await load()
    }

    public func isRecorded(_ event: CalendarEvent) -> Bool { recordedIds().contains(event.id) }
}
