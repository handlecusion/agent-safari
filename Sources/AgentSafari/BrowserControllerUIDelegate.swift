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

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        fputs("[agent-safari] alert suppressed: \(message)\n", stderr)
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        fputs("[agent-safari] confirm suppressed (returning false): \(message)\n", stderr)
        completionHandler(false)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        fputs("[agent-safari] prompt suppressed (returning \"\"): \(prompt)\n", stderr)
        completionHandler("")
    }
}
