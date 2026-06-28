import AppKit
import WebKit

/// Renders an HTML string to a PDF file via an offscreen `WKWebView` (PR 4).
///
/// `WKWebView.createPDF` requires the navigation to finish first, so we wait for `didFinish` before
/// snapshotting, and the instance retains itself across the async round-trip (otherwise it would be
/// deallocated the moment `write` returns and the callbacks would never fire). The HTML carries its own
/// `dir="rtl"` for Hebrew, so the PDF reads right-to-left.
@MainActor
final class PDFExporter: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var output: URL?
    private var retain: PDFExporter?

    /// Write `html` to a PDF at `url`. Fire-and-forget; the instance keeps itself alive until done.
    static func write(html: String, to url: URL) {
        let exporter = PDFExporter()
        exporter.retain = exporter
        exporter.output = url
        // US-Letter-ish frame; createPDF paginates the full content regardless of this size.
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 612, height: 792),
                            configuration: WKWebViewConfiguration())
        web.navigationDelegate = exporter
        exporter.webView = web
        web.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
            if case let .success(data) = result, let url = self?.output {
                try? data.write(to: url, options: .atomic)
            }
            self?.cleanup()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { cleanup() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) { cleanup() }

    private func cleanup() { webView = nil; retain = nil }
}
