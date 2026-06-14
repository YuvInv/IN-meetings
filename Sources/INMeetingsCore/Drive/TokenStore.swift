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

public enum KeychainError: Error { case unexpectedStatus(OSStatus) }

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
         kSecAttrAccount as String: account]
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
