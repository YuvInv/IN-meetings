import Foundation

/// Google OAuth 2.0 for installed apps (PKCE, no client secret). This type is **pure**: it builds the
/// authorization URL + token request bodies and decodes token responses, so it is fully unit-testable.
/// The interactive consent (`ASWebAuthenticationSession`) and the `URLSession` round-trips live in a
/// thin caller (`DriveAuth`), keeping the wire protocol here and verifiable without a browser.
public struct GoogleOAuth: Sendable {
    public struct Config: Sendable {
        public let clientID: String
        public let redirectScheme: String   // the reversed client id
        public let scopes: [String]

        public init(clientID: String, redirectScheme: String, scopes: [String]) {
            self.clientID = clientID
            self.redirectScheme = redirectScheme
            self.scopes = scopes
        }

        /// Custom-scheme callback the consent sheet redirects to (reversed client id + a path).
        public var redirectURI: String { "\(redirectScheme):/oauth2redirect" }
    }

    static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    public let config: Config
    public init(config: Config) { self.config = config }

    /// The authorization URL to open in the consent sheet. `access_type=offline` + `prompt=consent`
    /// ensure Google returns a refresh token so the app can stay connected without re-prompting.
    public func authorizationURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: Self.authEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url!
    }

    /// Form body to exchange an authorization `code` for tokens.
    public func tokenExchangeBody(code: String, verifier: String) -> Data {
        Self.form([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": config.clientID,
            "code_verifier": verifier,
            "redirect_uri": config.redirectURI,
        ])
    }

    /// Form body to refresh an access token using a stored refresh token.
    public func refreshBody(refreshToken: String) -> Data {
        Self.form([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
        ])
    }

    private static func form(_ params: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}

/// Google's token-endpoint response (authorization-code exchange and refresh).
public struct GoogleTokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    public let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}
