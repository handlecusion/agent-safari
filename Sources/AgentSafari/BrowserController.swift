import AgentSafariCore
import AppKit
import Darwin
import Foundation
import WebKit

@MainActor
final class BrowserController: NSObject, WKNavigationDelegate {
    let window: NSWindow
    let webView: WKWebView
    var navigationContinuation: CheckedContinuation<Void, Error>?
    var networkUserScriptInstalled = false
    var networkCaptureActive = false
    let sessionID = UUID().uuidString
    var activeTabID = "tab-1"

    init(focusWindow: Bool = false) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), configuration: configuration)
        self.webView.customUserAgent = BrowserUserAgentSettings.safariUserAgent
        self.window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        webView.navigationDelegate = self
        window.contentView = webView
        window.title = "Agent Safari"
        if focusWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.orderFrontRegardless()
        }
    }


}
