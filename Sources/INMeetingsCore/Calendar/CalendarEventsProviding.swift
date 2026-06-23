import Foundation

/// The slice of `CalendarContext` the day-agenda view model depends on — a seam so the model can be
/// unit-tested with a fake (no network, no Keychain).
public protocol CalendarEventsProviding: Sendable {
    var isConnected: Bool { get }
    func fetchEvents(timeMin: Date, timeMax: Date) async throws -> [CalendarEvent]
}

extension CalendarContext: CalendarEventsProviding {}
