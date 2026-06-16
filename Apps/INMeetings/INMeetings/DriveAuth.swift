import AppKit
import AuthenticationServices
import INMeetingsCore
import Observation

/// The interactive Google sign-in + backup-location picker for the menu (slice 6). Everything else
/// (token refresh, the Drive API, upload) lives in `INMeetingsCore`; this only runs the consent sheet
/// and writes the Keychain credential + the chosen `DriveLocation` — which `JobBridge`'s `DriveBackup`
/// then uses to auto-upload finished meetings.
@MainActor
@Observable
final class DriveAuth {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected(String)   // account email
        case failed(String)
    }

    private(set) var status: Status = .disconnected
    private(set) var sharedDrives: [DriveClient.DriveItem] = []
    private(set) var location: DriveLocation?

    private let oauth = GoogleOAuth(config: DriveConfig.oauth)
    private let tokenService = GoogleTokenService()
    private let tokenStore = KeychainTokenStore()
    private let locationStore = DriveLocationStore()
    @ObservationIgnored private lazy var tokens = DriveTokenManager(
        oauth: oauth, store: tokenStore, refresher: { [tokenService] body in try await tokenService.post(body) })
    @ObservationIgnored private lazy var client = DriveClient(token: { [tokens] in try await tokens.validAccessToken() })
    @ObservationIgnored private let anchor = AuthAnchor()
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?

    init() {
        location = locationStore.load()
        if let account = tokenStore.load()?.account, !account.isEmpty { status = .connected(account) }
    }

    var isConnected: Bool { if case .connected = status { return true }; return false }

    /// Run the Google consent sheet, store the credential, and load the user's Shared Drives.
    func connect() async {
        status = .connecting
        do {
            let pkce = PKCE.random()
            let state = UUID().uuidString
            let callback = try await present(oauth.authorizationURL(pkce: pkce, state: state))
            guard let code = Self.authorizationCode(from: callback, expectedState: state) else {
                throw DriveAuthError.refreshFailed
            }
            let response = try await tokenService.post(oauth.tokenExchangeBody(code: code, verifier: pkce.verifier))
            guard let initial = DriveCredential(response: response, account: "") else {
                throw DriveAuthError.refreshFailed
            }
            try tokenStore.save(initial)                       // store first so the client can authorize
            let email = (try? await client.accountEmail()) ?? "Google account"
            try tokenStore.save(DriveCredential(account: email, accessToken: initial.accessToken,
                                                refreshToken: initial.refreshToken, expiresAt: initial.expiresAt))
            status = .connected(email)
            await refreshSharedDrives()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func disconnect() {
        try? tokenStore.clear()
        locationStore.clear()
        location = nil
        sharedDrives = []
        status = .disconnected
    }

    func refreshSharedDrives() async {
        sharedDrives = (try? await client.listSharedDrives()) ?? []
    }

    /// Pick a Shared Drive: create/find an "IN Meetings" folder at its root and persist it as the target.
    func choose(_ drive: DriveClient.DriveItem) async {
        do {
            let folderID = try await client.findOrCreateFolder(name: "IN Meetings", parentID: drive.id, driveId: drive.id)
            let chosen = DriveLocation(driveID: drive.id, folderID: folderID,
                                       displayName: "\(drive.name) / IN Meetings")
            locationStore.save(chosen)
            location = chosen
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// A fresh OAuth access token to seed the Google Picker web view (refreshes if needed); nil if not
    /// connected.
    func pickerAccessToken() async -> String? {
        try? await tokens.validAccessToken()
    }

    /// Persist a folder the user picked in the Google Picker as the backup location. Resolves which Shared
    /// Drive the folder belongs to (nil = My Drive) so `DriveSync` scopes its calls correctly. The app
    /// creates `<Company>/<meeting>/` under exactly this folder.
    func chooseFolder(id: String, name: String) async {
        do {
            let info = try await client.fileInfo(id: id)
            let chosen = DriveLocation(driveID: info.driveId, folderID: id, displayName: name)
            locationStore.save(chosen)
            location = chosen
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Best-effort re-push of an edited metadata.json to a meeting's existing Drive folder (P1 rename).
    func reuploadMetadata(meetingFolderID: String, data: Data) async {
        await reuploadPackageFile("metadata.json", data: data, meetingFolderID: meetingFolderID)
    }

    /// Best-effort re-push of an edited JSON package file (metadata.json / transcript.json) to a meeting's
    /// existing Drive folder — keeps Drive in sync after a dashboard edit (company / speaker names).
    func reuploadPackageFile(_ name: String, data: Data, meetingFolderID: String) async {
        guard let location else { return }
        _ = try? await client.uploadOrReplaceFile(
            name: name, mimeType: "application/json",
            data: data, parentID: meetingFolderID, driveId: location.driveID)
    }

    // MARK: - Helpers

    private func present(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: DriveConfig.oauth.redirectScheme
            ) { [weak self] callbackURL, error in
                self?.authSession = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? DriveAuthError.refreshFailed)
                }
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                authSession = nil
                continuation.resume(throwing: DriveAuthError.refreshFailed)
            }
        }
    }

    static func authorizationCode(from callback: URL, expectedState: String) -> String? {
        guard let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "state" })?.value == expectedState else { return nil }
        return items.first(where: { $0.name == "code" })?.value
    }
}

/// Presentation anchor for the consent sheet. A menu-bar (`LSUIElement`) app has no main window, so we
/// fall back to a transient one. (If the sheet fails to appear in the menu-bar app, this anchor is the
/// thing to revisit — the alternative is a browser redirect via the registered URL scheme.)
private final class AuthAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.windows.first ?? NSWindow()
    }
}
