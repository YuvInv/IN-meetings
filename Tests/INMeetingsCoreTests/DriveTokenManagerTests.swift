import XCTest
@testable import INMeetingsCore

final class DriveTokenManagerTests: XCTestCase {
    private let oauth = GoogleOAuth(config: .init(clientID: "c", redirectScheme: "s", scopes: ["x"]))

    private func token(_ json: String) throws -> GoogleTokenResponse {
        try JSONDecoder().decode(GoogleTokenResponse.self, from: Data(json.utf8))
    }

    func testReturnsStoredTokenWhenNotExpired() async throws {
        let store = InMemoryTokenStore(DriveCredential(
            account: "a@in-venture.com", accessToken: "valid", refreshToken: "r",
            expiresAt: Date(timeIntervalSince1970: 10_000)))
        let manager = DriveTokenManager(oauth: oauth, store: store, refresher: { _ in
            XCTFail("must not refresh a still-valid token")
            throw DriveAuthError.refreshFailed
        })
        let access = try await manager.validAccessToken(now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(access, "valid")
    }

    func testRefreshesWhenExpiredPersistsAndCarriesRefreshTokenForward() async throws {
        let store = InMemoryTokenStore(DriveCredential(
            account: "a@in-venture.com", accessToken: "old", refreshToken: "1//keep",
            expiresAt: Date(timeIntervalSince1970: 100)))
        let manager = DriveTokenManager(oauth: oauth, store: store, refresher: { [self] _ in
            try token(#"{"access_token":"fresh","expires_in":3600,"token_type":"Bearer"}"#)
        })
        let access = try await manager.validAccessToken(now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(access, "fresh")
        XCTAssertEqual(store.load()?.accessToken, "fresh")
        XCTAssertEqual(store.load()?.refreshToken, "1//keep")  // refresh response omitted it
    }

    func testThrowsWhenNotConnected() async {
        let manager = DriveTokenManager(oauth: oauth, store: InMemoryTokenStore(), refresher: { _ in
            throw DriveAuthError.refreshFailed
        })
        do {
            _ = try await manager.validAccessToken()
            XCTFail("expected notConnected")
        } catch {
            XCTAssertEqual(error as? DriveAuthError, .notConnected)
        }
    }
}
