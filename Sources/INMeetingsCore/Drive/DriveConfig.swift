import Foundation

/// Static, non-secret configuration for the Google Drive integration.
///
/// The OAuth **client ID** identifies this app to Google — it is *not* a secret (there is no client
/// secret in the PKCE installed-app flow), so it lives in source.
///
/// The backup **destination is deliberately not here**: each user connects their own IN Venture Google
/// account and chooses a Drive location at runtime, which is persisted per user (ADR-006). Nothing
/// about where meetings back up is hardcoded.
public enum DriveConfig {
    public static let oauth = GoogleOAuth.Config(
        clientID: "1062382667236-p1ignhh12l0e9al7he5esph13s8lm1qf.apps.googleusercontent.com",
        redirectScheme: "com.googleusercontent.apps.1062382667236-p1ignhh12l0e9al7he5esph13s8lm1qf",
        scopes: [
            "https://www.googleapis.com/auth/drive",
            "https://www.googleapis.com/auth/calendar.events.readonly",
        ]
    )
}
