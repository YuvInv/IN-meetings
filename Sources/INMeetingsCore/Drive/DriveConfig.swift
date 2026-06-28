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

    // MARK: - Google Picker (the in-app Drive web-view folder picker)

    /// The Google Picker **browser API key**. Unlike the OAuth token, this is not a data-access secret —
    /// it only enables the Picker UI to load; access is still authorized by the per-user OAuth token. It
    /// must be provisioned in GCP project **1062382667236** (enable the *Google Picker API*, create a
    /// *Browser key*), then **supplied at run/build time — NOT pasted into source.**
    ///
    /// Supply it via the `GOOGLE_PICKER_API_KEY` environment variable (dev), or bake it into the release
    /// build from a gitignored xcconfig / CI secret. Always **restrict** the key in the Cloud Console to
    /// the Picker API + an HTTP referrer (`https://localhost/*`). Do NOT commit the literal: this repo can
    /// be public, and `AIza…` keys in public repos get scraped + abused (and auto-disabled by Google).
    public static var pickerAPIKey: String {
        ProcessInfo.processInfo.environment["GOOGLE_PICKER_API_KEY"] ?? pickerAPIKeyDefault
    }
    /// Intentionally empty — the key is injected via `GOOGLE_PICKER_API_KEY` (see above), never committed.
    /// Empty ⇒ the picker shows a "not configured yet" panel with setup steps instead of a broken web view.
    static let pickerAPIKeyDefault = ""

    /// The GCP **project number** (the numeric prefix of the OAuth client id) — required by the Picker.
    public static let pickerAppID = "1062382667236"

    /// The document origin the picker page loads under in the WKWebView. Add this to the API key's HTTP
    /// referrer allowlist (or leave the key unrestricted) so the Picker accepts the request.
    public static let pickerOrigin = "https://localhost/"

    /// True once the browser API key is set (env or source); gates the picker UI.
    public static var isPickerConfigured: Bool { !pickerAPIKey.isEmpty }

    /// The self-contained HTML that hosts the Google Picker, seeded with the user's OAuth `token` plus the
    /// browser key + app id. Folders only (My Drive + Shared Drives); the pick is posted back to Swift via
    /// `window.webkit.messageHandlers.picker`.
    public static func pickerHTML(token: String) -> String {
        let cfg: [String: String] = ["token": token, "apiKey": pickerAPIKey, "appId": pickerAppID]
        let json = (try? String(decoding: JSONSerialization.data(withJSONObject: cfg), as: UTF8.self)) ?? "{}"
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="margin:0;background:#1e1e1e">
        <script>
          var CFG = \(json);
          function onApiLoad(){ gapi.load('picker', onPickerLoad); }
          function onPickerLoad(){
            var mine = new google.picker.DocsView(google.picker.ViewId.FOLDERS)
              .setSelectFolderEnabled(true).setIncludeFolders(true)
              .setMimeTypes('application/vnd.google-apps.folder');
            var shared = new google.picker.DocsView(google.picker.ViewId.FOLDERS)
              .setSelectFolderEnabled(true).setIncludeFolders(true).setEnableDrives(true)
              .setMimeTypes('application/vnd.google-apps.folder');
            var picker = new google.picker.PickerBuilder()
              .setOAuthToken(CFG.token).setDeveloperKey(CFG.apiKey).setAppId(CFG.appId)
              .enableFeature(google.picker.Feature.SUPPORT_DRIVES)
              .addView(mine).addView(shared)
              .setTitle('Choose a backup folder')
              .setCallback(cb).build();
            picker.setVisible(true);
          }
          function cb(d){
            var a = d[google.picker.Response.ACTION];
            if (a == google.picker.Action.PICKED){
              var doc = d[google.picker.Response.DOCUMENTS][0];
              post({ id: doc[google.picker.Document.ID], name: doc[google.picker.Document.NAME] });
            } else if (a == google.picker.Action.CANCEL){ post({ cancelled: true }); }
          }
          function post(m){ try{ window.webkit.messageHandlers.picker.postMessage(m); }catch(e){} }
          window.onerror = function(m){ post({ error: String(m) }); };
        </script>
        <script async defer src="https://apis.google.com/js/api.js" onload="onApiLoad()"
          onerror="post({error:'Failed to load the Google API — check network and the API key referrer settings.'})"></script>
        </body></html>
        """
    }
}
