import Foundation
import os

private let driveLog = Logger(subsystem: "com.in-venture.in-meetings", category: "drive")

/// Write-through Drive backup (ADR-006), assembled from the stored credential + the user's chosen
/// location. The app only has to (a) sign in — which writes the Keychain credential — and (b) pick a
/// location — which writes the location store; this then runs automatically when a meeting finishes
/// (invoked by `JobBridge`). Best-effort: never throws into the recording flow.
public final class DriveBackup: @unchecked Sendable {
    private let meetingStore: MeetingStore
    private let tokenStore: TokenStore
    private let locationStore: DriveLocationStore
    private let sync: DriveSync

    public init(meetingStore: MeetingStore,
                tokenStore: TokenStore = KeychainTokenStore(),
                locationStore: DriveLocationStore = DriveLocationStore(),
                session: URLSession = .shared) {
        self.meetingStore = meetingStore
        self.tokenStore = tokenStore
        self.locationStore = locationStore

        let oauth = GoogleOAuth(config: DriveConfig.oauth)
        let tokenService = GoogleTokenService(session: session)
        let tokens = DriveTokenManager(oauth: oauth, store: tokenStore,
                                       refresher: { try await tokenService.post($0) })
        let client = DriveClient(token: { try await tokens.validAccessToken() }, session: session)
        self.sync = DriveSync(client: client, store: meetingStore)
    }

    /// True once an account is connected *and* a backup location is chosen.
    public var isConfigured: Bool { tokenStore.load() != nil && locationStore.load() != nil }

    /// Upload a finished package if backup is configured; otherwise a no-op. A failure is logged and
    /// recorded as `syncState = "failed"` in the index, never thrown into the recording flow.
    public func syncIfConfigured(meetingID: String, packageFolder: URL) async {
        guard tokenStore.load() != nil, let location = locationStore.load() else { return }
        do {
            let result = try await sync.sync(meetingID: meetingID, packageFolder: packageFolder, into: location)
            driveLog.notice("drive backup \(meetingID, privacy: .public) → \(result.meetingFolderID, privacy: .public) (\(result.uploaded.count) files)")
        } catch {
            driveLog.error("drive backup failed for \(meetingID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            try? meetingStore.setSyncState(id: meetingID, driveFolderId: nil, syncState: "failed")
        }
    }
}
