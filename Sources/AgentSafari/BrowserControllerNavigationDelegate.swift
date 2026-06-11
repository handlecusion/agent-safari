import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === activeTabWebView {
            updateAddressBar(webView.url?.absoluteString ?? "")
            window.title = webView.title.map { "Agent Safari — \($0)" } ?? "Agent Safari"
        }
        updateTabStrip()
        navigationContinuations.removeValue(forKey: ObjectIdentifier(webView))?.resume()
    }

    // A response WebKit cannot display (e.g. Content-Disposition: attachment, or an
    // unrenderable MIME type) becomes a download instead of a frame load. WebKit imports
    // this delegate method as async with a @MainActor result, so the completion-handler
    // form would not match the selector and would be skipped.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    // Anchors with a `download` attribute ask WebKit to download instead of navigate.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        navigationAction.shouldPerformDownload ? .download : .allow
    }

    // A navigation that became a download must not leave navigate() hanging: resume the
    // pending continuation (success, not error) and record download-started evidence the
    // triggering command drains. WebKit also fires didFailProvisionalNavigation with
    // WebKitErrorFrameLoadInterruptedByPolicyChange (102); whichever callback runs first
    // resumes the continuation, and didFailProvisionalNavigation swallows 102 so a
    // download is never reported as a navigation error.
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        navigationContinuations.removeValue(forKey: ObjectIdentifier(webView))?.resume()
        beginDownload(download, originatingWebView: webView)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        navigationContinuations.removeValue(forKey: ObjectIdentifier(webView))?.resume()
        beginDownload(download, originatingWebView: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateTabStrip()
        navigationContinuations.removeValue(forKey: ObjectIdentifier(webView))?.resume(throwing: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        // 102 = WebKitErrorFrameLoadInterruptedByPolicyChange: emitted when a response is
        // turned into a download. Resume successfully so navigate() reports the download
        // (via didBecome evidence) instead of a spurious "Frame load interrupted" error.
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            updateTabStrip()
            navigationContinuations.removeValue(forKey: ObjectIdentifier(webView))?.resume()
            return
        }
        updateTabStrip()
        navigationContinuations.removeValue(forKey: ObjectIdentifier(webView))?.resume(throwing: error)
    }
}
