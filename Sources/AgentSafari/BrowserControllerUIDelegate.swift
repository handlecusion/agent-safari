import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        let urlString = url.absoluteString
        Task { @MainActor in
            do {
                _ = try await navigate(urlString)
            } catch { fputs("[agent-safari] popup redirect navigation failed: \(error.localizedDescription)\n", stderr) }
        }
        pendingPopupRedirectURL = urlString
        return nil
    }
}
