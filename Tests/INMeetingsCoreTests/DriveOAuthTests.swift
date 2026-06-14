import XCTest
@testable import INMeetingsCore

/// The OAuth wire protocol (PKCE + authorization URL + token bodies) is pure and verifiable without a
/// browser. The interactive sign-in is checked live once `DriveAuth` lands.
final class DriveOAuthTests: XCTestCase {
    /// RFC 7636 Appendix B test vector — proves the S256 challenge derivation.
    func testPKCEChallengeMatchesRFCVector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(pkce.method, "S256")
    }

    func testRandomPKCEIsBase64URLAndDerivesItsChallenge() {
        let pkce = PKCE.random()
        XCTAssertFalse(pkce.verifier.contains(where: { "+/=".contains($0) }))
        XCTAssertGreaterThanOrEqual(pkce.verifier.count, 43)
        XCTAssertEqual(PKCE(verifier: pkce.verifier).challenge, pkce.challenge)
    }

    private var oauth: GoogleOAuth {
        GoogleOAuth(config: .init(
            clientID: "client123.apps.googleusercontent.com",
            redirectScheme: "com.googleusercontent.apps.client123",
            scopes: ["https://www.googleapis.com/auth/drive"]))
    }

    func testAuthorizationURLHasRequiredParams() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = oauth.authorizationURL(pkce: pkce, state: "xyz")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(value("client_id"), "client123.apps.googleusercontent.com")
        XCTAssertEqual(value("redirect_uri"), "com.googleusercontent.apps.client123:/oauth2redirect")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("code_challenge"), pkce.challenge)
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("access_type"), "offline")   // required to receive a refresh token
        XCTAssertEqual(value("state"), "xyz")
        XCTAssertEqual(value("scope"), "https://www.googleapis.com/auth/drive")
    }

    func testTokenExchangeBodyIsWellFormed() {
        let body = String(decoding: oauth.tokenExchangeBody(code: "AUTH_CODE", verifier: "VERIFIER"), as: UTF8.self)
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=AUTH_CODE"))
        XCTAssertTrue(body.contains("code_verifier=VERIFIER"))
        XCTAssertTrue(body.contains("client_id=client123.apps.googleusercontent.com"))
    }

    func testDecodeTokenResponse() throws {
        let json = #"{"access_token":"ya29.abc","refresh_token":"1//xyz","expires_in":3599,"token_type":"Bearer"}"#
        let token = try JSONDecoder().decode(GoogleTokenResponse.self, from: Data(json.utf8))
        XCTAssertEqual(token.accessToken, "ya29.abc")
        XCTAssertEqual(token.refreshToken, "1//xyz")
        XCTAssertEqual(token.expiresIn, 3599)
        XCTAssertEqual(token.tokenType, "Bearer")
    }

    func testProductionConfigIsTheInVentureClient() {
        XCTAssertTrue(DriveConfig.oauth.clientID.hasPrefix("1062382667236-"))
        XCTAssertEqual(DriveConfig.oauth.redirectURI,
                       "com.googleusercontent.apps.1062382667236-p1ignhh12l0e9al7he5esph13s8lm1qf:/oauth2redirect")
        XCTAssertTrue(DriveConfig.oauth.scopes.contains("https://www.googleapis.com/auth/drive"))
    }
}
