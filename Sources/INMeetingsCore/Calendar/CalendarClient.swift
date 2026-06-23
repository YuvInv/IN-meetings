import Foundation

public enum CalendarError: Error, Sendable { case http(status: Int, body: String) }

/// Minimal Google Calendar v3 client. Like `DriveClient`, the request building + decoding are pure
/// static helpers (unit-tested); execution goes through an injected token provider + `URLSession`.
public final class CalendarClient: @unchecked Sendable {
    public typealias TokenProvider = @Sendable () async throws -> String

    private let token: TokenProvider
    private let session: URLSession

    public init(token: @escaping TokenProvider, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    static let apiBase = URL(string: "https://www.googleapis.com/calendar/v3")!
    static let fields = "items(id,summary,start,end,hangoutLink,attendees(email,displayName,organizer))"

    // MARK: - Pure helpers (unit-tested)

    /// Windowed events query on the user's `primary` calendar (timed, expanded, time-ordered).
    static func eventsURL(timeMin: Date, timeMax: Date, maxResults: Int = 10) -> URL {
        let iso = ISO8601DateFormatter()
        var components = URLComponents(url: apiBase.appendingPathComponent("calendars/primary/events"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: timeMin)),
            URLQueryItem(name: "timeMax", value: iso.string(from: timeMax)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "fields", value: fields),
        ]
        return components.url!
    }

    static func decodeEvents(_ data: Data) throws -> [CalendarEvent] {
        try JSONDecoder().decode(EventsResponse.self, from: data).items ?? []
    }

    // MARK: - API

    /// Candidate events overlapping the window. Throws on a non-2xx response (caller degrades).
    public func fetchEvents(timeMin: Date, timeMax: Date, maxResults: Int = 10) async throws -> [CalendarEvent] {
        var request = URLRequest(url: Self.eventsURL(timeMin: timeMin, timeMax: timeMax, maxResults: maxResults))
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CalendarError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try Self.decodeEvents(data)
    }
}

/// A Google Calendar v3 event (only the fields the assembler needs). Explicit inits keep it
/// constructible from tests; `self`/`responseStatus` etc. are intentionally not decoded.
public struct CalendarEvent: Decodable, Sendable {
    public struct When: Decodable, Sendable {
        public let dateTime: String?
        public let date: String?
        public init(dateTime: String?, date: String?) { self.dateTime = dateTime; self.date = date }
    }
    public struct Attendee: Decodable, Sendable {
        public let email: String?
        public let displayName: String?
        public let organizer: Bool?
        public init(email: String?, displayName: String?, organizer: Bool?) {
            self.email = email
            self.displayName = displayName
            self.organizer = organizer
        }
    }
    public let id: String
    public let summary: String?
    public let start: When
    public let end: When
    public let hangoutLink: String?
    public let attendees: [Attendee]?
    public init(id: String, summary: String?, start: When, end: When,
                hangoutLink: String?, attendees: [Attendee]?) {
        self.id = id
        self.summary = summary
        self.start = start
        self.end = end
        self.hangoutLink = hangoutLink
        self.attendees = attendees
    }
}

struct EventsResponse: Decodable { let items: [CalendarEvent]? }
