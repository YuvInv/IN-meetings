import Foundation
import Security

/// Persistence for the connected-account credential. Abstracted behind a protocol so the auth logic is
/// testable with an in-memory store; the app uses the Keychain implementation.
public protocol TokenStore: Sendable {
    func load() -> DriveCredential?
    func save(_ credential: DriveCredential) throws
    func clear() throws
}

/// In-memory store — for tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var credential: DriveCredential?
    public init(_ credential: DriveCredential? = nil) { self.credential = credential }
    public func load() -> DriveCredential? { credential }
    public func save(_ credential: DriveCredential) throws { self.credential = credential }
    public func clear() throws { credential = nil }
}

public enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)

    /// A human message (and the real `OSStatus`) instead of Swift's default "KeychainError error 0" — the
    /// bare enum-ordinal rendering hides which keychain call failed and why.
    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String?
            return "Keychain error \(status)" + (detail.map { " — \($0)" } ?? "")
        }
    }
}

/// Keychain-backed store: one generic-password item holding the JSON-encoded credential.
public final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(service: String = "com.in-venture.in-meetings.drive", account: String = "google-oauth") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         // Use the modern data-protection keychain: the item is owned by the app's team-prefixed
         // keychain-access-group (stable across binary renames/re-signs), not the login keychain's
         // per-binary ACL — which rejected writes with errSecInvalidOwnerEdit (-25244) after a re-sign.
         // With a single keychain-access-group entitlement, that group is used by default (no explicit
         // kSecAttrAccessGroup needed), which also keeps this Core type free of the team prefix.
         kSecUseDataProtectionKeychain as String: true]
    }

    public func load() -> DriveCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(DriveCredential.self, from: data)
    }

    public func save(_ credential: DriveCredential) throws {
        let data = try JSONEncoder().encode(credential)
        try clear()   // generic-password items aren't upserted — replace
        var query = baseQuery
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
