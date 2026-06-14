import Foundation

/// A connected Google account's tokens, persisted (Keychain) so the app stays signed in across launches.
public struct DriveCredential: Codable, Sendable, Equatable {
    public let account: String          // the connected Google account email
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(account: String, accessToken: String, refreshToken: String, expiresAt: Date) {
        self.account = account
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Build from a token-endpoint response. A **refresh** response usually omits the refresh token, so
    /// the existing one is carried forward via `fallbackRefreshToken`. Returns nil if neither is present
    /// (which would mean we can't stay connected — the caller should surface a re-auth).
    public init?(response: GoogleTokenResponse, account: String,
                 issuedAt: Date = Date(), fallbackRefreshToken: String? = nil) {
        guard let refresh = response.refreshToken ?? fallbackRefreshToken else { return nil }
        self.init(account: account,
                  accessToken: response.accessToken,
                  refreshToken: refresh,
                  expiresAt: issuedAt.addingTimeInterval(TimeInterval(response.expiresIn)))
    }

    /// True when the access token is at/near expiry (default 60s leeway) and should be refreshed first.
    public func isExpired(asOf now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}
