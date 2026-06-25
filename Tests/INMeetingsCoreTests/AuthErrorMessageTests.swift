import XCTest
@testable import INMeetingsCore

/// The keychain/auth errors used to render as Swift's default "INMeetingsCore.KeychainError error 0"
/// (the enum-case ordinal), which is what the dashboard calendar panel showed. These assert the
/// `LocalizedError` messages now carry actionable / diagnostic text instead.
final class AuthErrorMessageTests: XCTestCase {
    func testKeychainErrorSurfacesRealStatusNotOrdinal() {
        let err = KeychainError.unexpectedStatus(-25300)   // errSecItemNotFound
        XCTAssertTrue((err.errorDescription ?? "").contains("-25300"),
                      "expected the real OSStatus in the message, got: \(err.errorDescription ?? "nil")")
        XCTAssertFalse(err.localizedDescription.contains("error 0"), err.localizedDescription)
    }

    func testDriveAuthErrorMessagesAreActionable() {
        XCTAssertTrue((DriveAuthError.notConnected.errorDescription ?? "").contains("Connect"))
        XCTAssertTrue((DriveAuthError.refreshFailed.errorDescription ?? "").contains("Reconnect"))
        XCTAssertFalse(DriveAuthError.notConnected.localizedDescription.contains("error 0"))
    }
}
