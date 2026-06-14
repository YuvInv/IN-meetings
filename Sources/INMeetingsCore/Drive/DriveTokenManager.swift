import Foundation

public enum DriveAuthError: Error, Sendable, Equatable { case notConnected, refreshFailed }

/// Supplies a valid Drive access token, transparently refreshing (and persisting) it when expired.
/// The network refresh is **injected** so the refresh decision + token carry-forward are unit-tested;
/// the app wires the real `URLSession` POST to the token endpoint. An `actor` so concurrent callers
/// don't trigger overlapping refreshes.
public actor DriveTokenManager {
    public typealias Refresher = @Sendable (_ body: Data) async throws -> GoogleTokenResponse

    private let oauth: GoogleOAuth
    private let store: TokenStore
    private let refresher: Refresher

    public init(oauth: GoogleOAuth, store: TokenStore, refresher: @escaping Refresher) {
        self.oauth = oauth
        self.store = store
        self.refresher = refresher
    }

    public var isConnected: Bool { store.load() != nil }
    public var account: String? { store.load()?.account }

    /// A non-expired access token, refreshing first if needed. Throws `.notConnected` when no credential
    /// is stored (the user hasn't connected an account yet).
    public func validAccessToken(now: Date = Date()) async throws -> String {
        guard let current = store.load() else { throw DriveAuthError.notConnected }
        guard current.isExpired(asOf: now) else { return current.accessToken }

        let response = try await refresher(oauth.refreshBody(refreshToken: current.refreshToken))
        guard let refreshed = DriveCredential(response: response, account: current.account,
                                              fallbackRefreshToken: current.refreshToken) else {
            throw DriveAuthError.refreshFailed
        }
        try store.save(refreshed)
        return refreshed.accessToken
    }
}
