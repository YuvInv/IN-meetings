import CryptoKit
import Foundation

/// PKCE (RFC 7636) for Google's installed-app OAuth flow — lets the app authenticate without a client
/// secret (the iOS-type client has none). The verifier is held in memory for one sign-in; the derived
/// challenge is sent in the authorization request and proves possession at the token exchange.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String
    public let method = "S256"

    /// Derives the S256 challenge from a given verifier (deterministic — used by `random()` and tests).
    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = base64URLNoPad(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// A fresh, cryptographically-random verifier (32 random bytes → a 43-char base64url string).
    public static func random() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return PKCE(verifier: base64URLNoPad(Data(bytes)))
    }
}

/// base64url without padding (RFC 4648 §5) — the encoding PKCE uses for both verifier and challenge.
func base64URLNoPad(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
