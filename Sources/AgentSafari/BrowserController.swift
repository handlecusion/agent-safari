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
    let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 764))
    let chromeView = NSView(frame: NSRect(x: 0, y: 720, width: 1280, height: 44))
    let addressField = NSTextField(frame: NSRect(x: 14, y: 8, width: 1252, height: 28))
    let webContainerView = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
    static let addressBarHeight: CGFloat = 44
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
            contentRect: NSRect(x: 100, y: 100, width: 1280, height: 764),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        let initialWebView = makeWebView()
        tabsModel = [BrowserTab(id: activeTabID, webView: initialWebView, createdAt: Date())]
        configureBrowserChrome()
        attachWebViewToContainer(initialWebView)
        window.contentView = rootView
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
        attachWebViewToContainer(tab.webView)
        updateAddressBar(tab.webView.url?.absoluteString ?? "")
        window.title = tab.webView.title.map { "Agent Safari — \($0)" } ?? "Agent Safari"
    }

    func configureBrowserChrome() {
        rootView.autoresizingMask = [.width, .height]
        rootView.wantsLayer = true

        chromeView.autoresizingMask = [.width, .minYMargin]
        chromeView.wantsLayer = true
        chromeView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        addressField.placeholderString = "Enter URL or search"
        addressField.setAccessibilityIdentifier("agent-safari-address-bar")
        addressField.font = NSFont.systemFont(ofSize: 14)
        addressField.bezelStyle = .roundedBezel
        addressField.lineBreakMode = .byTruncatingMiddle
        addressField.target = self
        addressField.action = #selector(addressBarCommit(_:))
        addressField.autoresizingMask = [.width]

        webContainerView.autoresizingMask = [.width, .height]
        rootView.addSubview(webContainerView)
        rootView.addSubview(chromeView)
        chromeView.addSubview(addressField)
        layoutBrowserChrome()
    }

    func layoutBrowserChrome() {
        let bounds = rootView.bounds
        let chromeHeight = BrowserController.addressBarHeight
        chromeView.frame = NSRect(x: 0, y: max(0, bounds.height - chromeHeight), width: bounds.width, height: chromeHeight)
        addressField.frame = NSRect(x: 14, y: 8, width: max(120, bounds.width - 28), height: 28)
        webContainerView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(1, bounds.height - chromeHeight))
        webView.frame = webContainerView.bounds
    }

    func attachWebViewToContainer(_ targetWebView: WKWebView) {
        for subview in webContainerView.subviews where subview !== targetWebView {
            subview.removeFromSuperview()
        }
        if targetWebView.superview !== webContainerView {
            targetWebView.removeFromSuperview()
            webContainerView.addSubview(targetWebView)
        }
        targetWebView.frame = webContainerView.bounds
        targetWebView.autoresizingMask = [.width, .height]
    }

    func updateAddressBar(_ urlString: String) {
        addressField.stringValue = urlString
    }

    func normalizedAddressBarURL(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if URL(string: trimmed)?.scheme != nil { return trimmed }
        if trimmed.contains(".") && !trimmed.contains(" ") { return "https://\(trimmed)" }
        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return "https://www.google.com/search?q=\(query)"
    }

    @objc func addressBarCommit(_ sender: NSTextField) {
        guard let destination = normalizedAddressBarURL(sender.stringValue) else { return }
        updateAddressBar(destination)
        Task { @MainActor in
            do {
                _ = try await navigate(destination)
            } catch {
                updateAddressBar(destination)
            }
        }
    }

}
