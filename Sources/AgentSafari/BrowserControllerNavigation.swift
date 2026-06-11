import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    func navigate(_ urlString: String, in explicitTarget: WKWebView? = nil) async throws -> [String: String] {
        guard let url = URL(string: urlString), url.scheme != nil else {
            throw AgentSafariError.invalidURL(urlString)
        }
        let target = explicitTarget ?? webView
        let key = ObjectIdentifier(target)
        guard navigationContinuations[key] == nil else {
            throw AgentSafariError.navigationInProgress(tabID(for: target) ?? "unknown")
        }
        if isSameDocumentNavigation(to: url, in: target) {
            // WebKit performs same-document navigations (fragment-only changes) without
            // firing didFinish/didFail, so the load/continuation path would hang forever.
            // Drive the fragment change via JavaScript and return synchronously instead.
            let urlLiteral = try javaScriptStringLiteral(urlString)
            _ = try await target.evaluateJavaScript("location.href = \(urlLiteral)")
            if target === activeTabWebView { updateAddressBar(target.url?.absoluteString ?? urlString) }
            return [
                "url": target.url?.absoluteString ?? "",
                "title": target.title ?? "",
                "sameDocument": "true",
            ]
        }
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuations[key] = continuation
            if target === activeTabWebView { updateAddressBar(urlString) }
            target.load(URLRequest(url: url))
        }
        if target === activeTabWebView { updateAddressBar(target.url?.absoluteString ?? urlString) }
        return ["url": target.url?.absoluteString ?? "", "title": target.title ?? ""]
    }

    /// True when navigating to `target` only changes the fragment of the currently
    /// loaded document. WebKit handles this as a same-document navigation and does
    /// not invoke the navigation delegate callbacks that resume the continuation.
    func isSameDocumentNavigation(to target: URL, in webView: WKWebView) -> Bool {
        guard target.fragment != nil else { return false }
        guard let current = webView.url else { return false }
        return urlIgnoringFragment(current) == urlIgnoringFragment(target)
    }

    private func urlIgnoringFragment(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    func evaluate(_ script: String) async throws -> [String: String] {
        let value = try await webView.evaluateJavaScript(script)
        return ["value": stringifyJavaScriptValue(value as Any)]
    }

    func text() async throws -> [String: String] {
        let value = try await webView.evaluateJavaScript("document.body ? document.body.innerText : ''")
        return ["text": stringifyJavaScriptValue(value as Any)]
    }

    func html() async throws -> [String: String] {
        let value = try await webView.evaluateJavaScript("document.documentElement ? document.documentElement.outerHTML : ''")
        return ["html": stringifyJavaScriptValue(value as Any)]
    }

    func url() async throws -> [String: String] {
        ["url": webView.url?.absoluteString ?? ""]
    }

    func title() async throws -> [String: String] {
        ["title": webView.title ?? ""]
    }

    func back() async throws -> [String: String] {
        if webView.canGoBack { webView.goBack() }
        return ["url": webView.url?.absoluteString ?? "", "canGoBack": webView.canGoBack ? "true" : "false"]
    }

    func forward() async throws -> [String: String] {
        if webView.canGoForward { webView.goForward() }
        return ["url": webView.url?.absoluteString ?? "", "canGoForward": webView.canGoForward ? "true" : "false"]
    }

    func reload() async throws -> [String: String] {
        webView.reload()
        return ["url": webView.url?.absoluteString ?? "", "reloading": "true"]
    }

    func viewport(width: Int, height: Int) async throws -> [String: String] {
        let size = NSSize(width: max(1, width), height: max(1, height))
        window.setContentSize(NSSize(width: size.width, height: size.height + BrowserController.addressBarHeight))
        layoutBrowserChrome()
        webContainerView.setFrameSize(size)
        webView.setFrameSize(size)
        return ["width": String(Int(size.width)), "height": String(Int(size.height))]
    }
}
