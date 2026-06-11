import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === activeTabWebView {
            updateAddressBar(webView.url?.absoluteString ?? "")
        }
        navigationContinuations.removeValue(forKey: ObjectIdentifier(webView))?.resume()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuations.removeValue(forKey: ObjectIdentifier(webView))?.resume(throwing: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuations.removeValue(forKey: ObjectIdentifier(webView))?.resume(throwing: error)
    }
}
