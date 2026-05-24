import AgentSafariCore
import AppKit
import Darwin
import Foundation
import WebKit

@MainActor
struct BrowserTab {
    let id: String
    let webView: WKWebView
    var createdAt: Date
}

@MainActor
final class BrowserController: NSObject, WKNavigationDelegate {
    let window: NSWindow
    var tabsModel: [BrowserTab] = []
    var navigationContinuation: CheckedContinuation<Void, Error>?
    var networkUserScriptInstalled = false
    var networkCaptureActive = false
    let sessionID = UUID().uuidString
    let profileName: String
    let ephemeral: Bool
    var activeTabID: String

    var webView: WKWebView {
        guard let tab = tabsModel.first(where: { $0.id == activeTabID }) ?? tabsModel.first else {
            fatalError("BrowserController has no active WebKit tab")
        }
        return tab.webView
    }

    init(focusWindow: Bool = false, profileName: String = "default", ephemeral: Bool = false) {
        self.profileName = profileName
        self.ephemeral = ephemeral
        self.activeTabID = "tab-1"
        self.window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        let initialWebView = makeWebView()
        tabsModel = [BrowserTab(id: activeTabID, webView: initialWebView, createdAt: Date())]
        window.contentView = initialWebView
        window.title = "Agent Safari"
        if focusWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.orderFrontRegardless()
        }
    }

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = ephemeral ? .nonPersistent() : .default()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let newWebView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), configuration: configuration)
        newWebView.customUserAgent = BrowserUserAgentSettings.safariUserAgent
        newWebView.navigationDelegate = self
        return newWebView
    }

    func activateTab(id: String) throws {
        guard let tab = tabsModel.first(where: { $0.id == id }) else { throw AgentSafariError.unknownTab(id) }
        activeTabID = id
        tab.webView.frame = window.contentView?.bounds ?? tab.webView.frame
        tab.webView.autoresizingMask = [.width, .height]
        window.contentView = tab.webView
        window.title = tab.webView.title.map { "Agent Safari — \($0)" } ?? "Agent Safari"
    }

}
