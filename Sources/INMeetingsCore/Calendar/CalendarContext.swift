import Foundation
import os

private let calendarLog = Logger(subsystem: "com.in-venture.in-meetings", category: "calendar")

/// Phase-2 calendar context (ADR-004), Swift half: fetch candidate events around the meeting window and
/// write `<meeting>/context.input.json` for the Python assembler. Reuses the slice-6 Google credential
/// (Keychain) and the new `calendar.events.readonly` scope. A no-op when no account is connected or
/// anything fails — the pipeline then degrades to unbiased transcription.
public final class CalendarContext: @unchecked Sendable {
    private let tokenStore: TokenStore
    private let client: CalendarClient

    public init(tokenStore: TokenStore = KeychainTokenStore(),
                session: URLSession = CalendarContext.defaultSession) {
        self.tokenStore = tokenStore
        let oauth = GoogleOAuth(config: DriveConfig.oauth)
        let tokenService = GoogleTokenService(session: session)
        let tokens = DriveTokenManager(oauth: oauth, store: tokenStore,
                                       refresher: { try await tokenService.post($0) })
        self.client = CalendarClient(token: { try await tokens.validAccessToken() }, session: session)
    }

    /// A short-timeout session — the fetch sits in front of pipeline spawn, so it must not stall Stop.
    public static var defaultSession: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config)
    }

    public var isConnected: Bool { tokenStore.load() != nil }

    /// Fetch candidates for `[startedAt-90m, endedAt+30m]` and write context.input.json. Best-effort:
    /// no connected account, or any network/auth failure, simply writes nothing.
    public func writeInput(into directory: URL, startedAt: Date, endedAt: Date,
                           captureSourceApp: String?) async {
        guard let credential = tokenStore.load() else { return }
        let domain = Self.domain(ofEmail: credential.account)
        do {
            let events = try await client.fetchEvents(timeMin: startedAt.addingTimeInterval(-90 * 60),
                                                      timeMax: endedAt.addingTimeInterval(30 * 60))
            let payload = Self.inputPayload(internalDomain: domain, candidates: events,
                                            captureSourceApp: captureSourceApp,
                                            startedAt: startedAt, endedAt: endedAt)
            try Self.write(payload, into: directory)
            calendarLog.notice("calendar context written (\(events.count, privacy: .public) candidates)")
        } catch {
            // Surface the failure (status:"error") so a Calendar 403 shows up as calendar:"error" in
            // metadata + context.md, instead of looking like a silent "no event matched".
            calendarLog.error("calendar context failed: \(error.localizedDescription, privacy: .public)")
            try? Self.write(["status": "error", "error": error.localizedDescription], into: directory)
        }
    }

    /// Fetch events overlapping `[timeMin, timeMax]` (the calendar panel's per-day query). Higher
    /// `maxResults` than the live candidate fetch since a full day can hold many events.
    public func fetchEvents(timeMin: Date, timeMax: Date) async throws -> [CalendarEvent] {
        try await client.fetchEvents(timeMin: timeMin, timeMax: timeMax, maxResults: 250)
    }

    /// Write `context.input.json` pinned to ONE chosen event (the import path): the Python assembler
    /// matches by window overlap, so we set the hint window to the event's own start/end → a 100% overlap
    /// makes it the unambiguous match. No network call (the event is already in hand). Best-effort.
    public func writePinnedInput(into directory: URL, event: CalendarEvent, startedAt: Date, endedAt: Date) {
        let domain = tokenStore.load().map { Self.domain(ofEmail: $0.account) } ?? ""
        let payload = Self.inputPayload(internalDomain: domain, candidates: [event],
                                        captureSourceApp: nil, startedAt: startedAt, endedAt: endedAt)
        try? Self.write(payload, into: directory)
    }

    /// Atomically write a payload to `<meeting>/context.input.json`.
    static func write(_ payload: [String: Any], into directory: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("context.input.json"), options: .atomic)
    }

    // MARK: - Pure helpers (unit-tested)

    /// The lowercased domain of an email, or "" when malformed — feeds the internal/external split.
    static func domain(ofEmail email: String) -> String {
        guard let at = email.firstIndex(of: "@") else { return "" }
        return email[email.index(after: at)...].lowercased()
    }

    /// Flatten Calendar events + record-time hints into the context.input.json the Python assembler reads.
    static func inputPayload(internalDomain: String, candidates: [CalendarEvent],
                             captureSourceApp: String?, startedAt: Date, endedAt: Date) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        let cands: [[String: Any]] = candidates.map { event in
            [
                "id": event.id,
                "summary": event.summary ?? "",
                "start": event.start.dateTime ?? event.start.date ?? "",
                "end": event.end.dateTime ?? event.end.date ?? "",
                "has_link": event.hangoutLink != nil,
                "attendees": (event.attendees ?? []).map { attendee in
                    ["email": attendee.email ?? "",
                     "displayName": attendee.displayName ?? "",
                     "organizer": attendee.organizer ?? false] as [String: Any]
                },
            ]
        }
        return [
            "status": "ok",
            "internal_domain": internalDomain,
            "hints": ["capture_source_app": captureSourceApp ?? "",
                      "started_at": iso.string(from: startedAt),
                      "ended_at": iso.string(from: endedAt)],
            "candidates": cands,
        ]
    }
}
