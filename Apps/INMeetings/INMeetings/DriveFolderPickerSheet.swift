import SwiftUI
import WebKit
import INMeetingsCore

/// The interactive Google Drive folder picker (P1): a real Google Drive web view (the Google Picker API
/// in a `WKWebView`) where the user browses My Drive + Shared Drives and picks any folder as the backup
/// destination. The pick is bridged back to Swift and persisted by `DriveAuth.chooseFolder`.
///
/// Needs the browser API key in `DriveConfig` (env `GOOGLE_PICKER_API_KEY` or `pickerAPIKeyDefault`); when
/// it's missing we show setup steps rather than a blank page.
struct DriveFolderPickerSheet: View {
    let token: String
    let onPick: (_ id: String, _ name: String) -> Void
    let onClose: () -> Void

    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose a backup folder in Google Drive").font(.headline)
                Spacer()
                Button("Cancel") { onClose() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            content
        }
        .frame(width: 760, height: 580)
    }

    @ViewBuilder private var content: some View {
        if !DriveConfig.isPickerConfigured {
            notConfigured
        } else if let errorText {
            ContentUnavailableView {
                Label("Couldn’t load the picker", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorText)
            }
        } else {
            PickerWebView(html: DriveConfig.pickerHTML(token: token), onMessage: handle)
        }
    }

    private var notConfigured: some View {
        ContentUnavailableView {
            Label("Drive picker needs a one-time setup", systemImage: "key")
        } description: {
            Text("""
            The Google Picker needs a browser API key in GCP project 1062382667236:
            1. Google Cloud Console ▸ APIs & Services ▸ Library ▸ enable “Google Picker API”.
            2. Credentials ▸ Create credentials ▸ API key (Browser key).
            3. Either leave it unrestricted, or add referrer https://localhost/* to it.
            4. Paste it into DriveConfig.pickerAPIKeyDefault (or set GOOGLE_PICKER_API_KEY) and relaunch.
            """)
            .font(.callout)
        }
        .padding()
    }

    private func handle(_ body: [String: Any]) {
        if let id = body["id"] as? String, let name = body["name"] as? String {
            onPick(id, name)
        } else if body["cancelled"] != nil {
            onClose()
        } else if let err = body["error"] as? String {
            errorText = err
        }
    }
}

/// A `WKWebView` that loads the Google Picker HTML and forwards the picked folder (or cancel/error) to
/// Swift via a `picker` message handler.
private struct PickerWebView: NSViewRepresentable {
    let html: String
    let onMessage: ([String: Any]) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "picker")
        config.userContentController = controller
        let web = WKWebView(frame: .zero, configuration: config)
        // A real https baseURL so the Picker's referrer check has a stable origin (see DriveConfig).
        web.loadHTMLString(html, baseURL: URL(string: DriveConfig.pickerOrigin))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onMessage: onMessage) }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onMessage: ([String: Any]) -> Void
        init(onMessage: @escaping ([String: Any]) -> Void) { self.onMessage = onMessage }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any] { onMessage(body) }
        }
    }
}
