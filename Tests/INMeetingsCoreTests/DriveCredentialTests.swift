import XCTest
@testable import INMeetingsCore

final class DriveCredentialTests: XCTestCase {
    private func token(_ json: String) throws -> GoogleTokenResponse {
        try JSONDecoder().decode(GoogleTokenResponse.self, from: Data(json.utf8))
    }

    func testExpiryRespectsLeeway() {
        let c = DriveCredential(account: "a@in-venture.com", accessToken: "t", refreshToken: "r",
                                expiresAt: Date(timeIntervalSince1970: 1000))
        XCTAssertFalse(c.isExpired(asOf: Date(timeIntervalSince1970: 900), leeway: 60))  // 960 < 1000
        XCTAssertTrue(c.isExpired(asOf: Date(timeIntervalSince1970: 950), leeway: 60))   // 1010 >= 1000
    }

    func testInitialExchangeCapturesRefreshToken() throws {
        let resp = try token(#"{"access_token":"ya29.a","refresh_token":"1//r","expires_in":3600,"token_type":"Bearer"}"#)
        let c = DriveCredential(response: resp, account: "a@in-venture.com", issuedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(c?.accessToken, "ya29.a")
        XCTAssertEqual(c?.refreshToken, "1//r")
        XCTAssertEqual(c?.expiresAt, Date(timeIntervalSince1970: 3600))
    }

    func testRefreshResponseCarriesForwardExistingRefreshToken() throws {
        // Google's refresh responses omit refresh_token — we must keep the one we already have.
        let resp = try token(#"{"access_token":"ya29.new","expires_in":3600,"token_type":"Bearer"}"#)
        XCTAssertNil(DriveCredential(response: resp, account: "a@in-venture.com"))  // no fallback ⇒ nil
        let c = DriveCredential(response: resp, account: "a@in-venture.com", fallbackRefreshToken: "1//keep")
        XCTAssertEqual(c?.accessToken, "ya29.new")
        XCTAssertEqual(c?.refreshToken, "1//keep")
    }

    func testInMemoryStoreRoundTrips() throws {
        let store = InMemoryTokenStore()
        XCTAssertNil(store.load())
        let c = DriveCredential(account: "a@in-venture.com", accessToken: "t", refreshToken: "r",
                                expiresAt: Date(timeIntervalSince1970: 5000))
        try store.save(c)
        XCTAssertEqual(store.load(), c)
        try store.clear()
        XCTAssertNil(store.load())
    }
}
