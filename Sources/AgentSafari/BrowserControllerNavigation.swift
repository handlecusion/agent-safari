import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    func navigate(_ urlString: String) async throws -> [String: String] {
        guard let url = URL(string: urlString) else {
            throw AgentSafariError.invalidURL(urlString)
        }
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            updateAddressBar(urlString)
            webView.load(URLRequest(url: url))
        }
        updateAddressBar(webView.url?.absoluteString ?? urlString)
        return ["url": webView.url?.absoluteString ?? "", "title": webView.title ?? ""]
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
