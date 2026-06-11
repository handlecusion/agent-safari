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

/// One observed download. State moves pending -> completed|failed. `tabId` is the
/// modeled tab that originated the download when resolvable, else the active tab.
@MainActor
final class DownloadRecord {
    let id: String
    let url: String
    var suggestedFilename: String
    var path: String
    var state: String
    var error: String?
    let tabId: String

    init(id: String, url: String, suggestedFilename: String, path: String, tabId: String) {
        self.id = id
        self.url = url
        self.suggestedFilename = suggestedFilename
        self.path = path
        self.state = "pending"
        self.error = nil
        self.tabId = tabId
    }
}

/// Per-command tab targeting. The RPC layer binds the requested tab id for the
/// duration of one command Task; controller code resolves `webView` through it.
enum TabTarget {
    @TaskLocal static var tabID: String?
}

/// Per-command JS dialog confirm policy. Confirm dialogs fire synchronously
/// inside the command's JS evaluation, so a task-local applies for the duration
/// of one command Task. Values: "accept" | "dismiss" (nil = dismiss).
enum DialogPolicy {
    @TaskLocal static var confirm: String?
}

@MainActor
final class BrowserController: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let window: NSWindow
    let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 764))
    let chromeView = NSView(frame: NSRect(x: 0, y: 720, width: 1280, height: 44))
    let addressField = NSTextField(frame: NSRect(x: 14, y: 8, width: 1252, height: 28))
    let webContainerView = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
    static let addressBarHeight: CGFloat = 44
    var tabsModel: [BrowserTab] = []
    var navigationContinuations: [ObjectIdentifier: CheckedContinuation<Void, Error>] = [:]
    private var networkUserScriptInstalledByTab: [ObjectIdentifier: Bool] = [:]
    var networkCaptureActiveByTab: [ObjectIdentifier: Bool] = [:]
    private var consoleUserScriptInstalledByTab: [ObjectIdentifier: Bool] = [:]
    var consoleCaptureActiveByTab: [ObjectIdentifier: Bool] = [:]
    private var pendingPopupRedirectURLByTab: [ObjectIdentifier: String] = [:]
    var pendingSuppressedDialogsByTab: [ObjectIdentifier: [String]] = [:]
    private var pendingUploadFileURLsByTab: [ObjectIdentifier: [URL]] = [:]
    private var pendingDownloadStartedByTab: [ObjectIdentifier: String] = [:]
    // Daemon-wide download log capped at downloadModelCap entries (oldest completed dropped first).
    var downloadsModel: [DownloadRecord] = []
    let downloadModelCap = 50
    // Maps an in-flight WKDownload to its DownloadRecord id for delegate callbacks.
    var downloadRecordsByDownload: [ObjectIdentifier: String] = [:]
    let sessionID = UUID().uuidString
    let profileName: String
    let ephemeral: Bool
    var activeTabID: String

    /// Resolves to the command's target tab (TabTarget task-local) or the active tab.
    /// The RPC layer validates unknown tab ids before dispatch and re-checks after
    /// completion, so a fallback here only happens if the tab closed mid-command.
    var webView: WKWebView {
        let targetID = TabTarget.tabID ?? activeTabID
        guard let tab = tabsModel.first(where: { $0.id == targetID }) ?? tabsModel.first else {
            fatalError("BrowserController has no WebKit tabs")
        }
        return tab.webView
    }

    var activeTabWebView: WKWebView {
        guard let tab = tabsModel.first(where: { $0.id == activeTabID }) ?? tabsModel.first else {
            fatalError("BrowserController has no WebKit tabs")
        }
        return tab.webView
    }

    func hasTab(_ id: String) -> Bool {
        tabsModel.contains { $0.id == id }
    }

    func tabID(for webView: WKWebView) -> String? {
        tabsModel.first { $0.webView === webView }?.id
    }

    // Per-tab state exposed under the original property names so call sites and
    // the network/popup logic stay tab-correct without signature changes.
    var networkUserScriptInstalled: Bool {
        get { networkUserScriptInstalledByTab[ObjectIdentifier(webView)] ?? false }
        set { networkUserScriptInstalledByTab[ObjectIdentifier(webView)] = newValue }
    }

    var networkCaptureActive: Bool {
        get { networkCaptureActiveByTab[ObjectIdentifier(webView)] ?? false }
        set { networkCaptureActiveByTab[ObjectIdentifier(webView)] = newValue }
    }

    var consoleUserScriptInstalled: Bool {
        get { consoleUserScriptInstalledByTab[ObjectIdentifier(webView)] ?? false }
        set { consoleUserScriptInstalledByTab[ObjectIdentifier(webView)] = newValue }
    }

    var consoleCaptureActive: Bool {
        get { consoleCaptureActiveByTab[ObjectIdentifier(webView)] ?? false }
        set { consoleCaptureActiveByTab[ObjectIdentifier(webView)] = newValue }
    }

    var pendingPopupRedirectURL: String? {
        get { pendingPopupRedirectURLByTab[ObjectIdentifier(webView)] }
        set { pendingPopupRedirectURLByTab[ObjectIdentifier(webView)] = newValue }
    }

    func setPendingPopupRedirectURL(_ url: String, for webView: WKWebView) {
        pendingPopupRedirectURLByTab[ObjectIdentifier(webView)] = url
    }

    var pendingSuppressedDialogs: [String] {
        get { pendingSuppressedDialogsByTab[ObjectIdentifier(webView)] ?? [] }
        set { pendingSuppressedDialogsByTab[ObjectIdentifier(webView)] = newValue }
    }

    // Records suppressed-dialog evidence keyed by the DELEGATE's webView, which is
    // the originating (possibly background) tab — not necessarily the active one.
    // Capped at 20 entries per tab (oldest dropped) so runaway dialog loops can't
    // grow the buffer without bound.
    func appendSuppressedDialog(_ entry: String, for webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        var entries = pendingSuppressedDialogsByTab[key] ?? []
        entries.append(entry)
        if entries.count > 20 { entries.removeFirst(entries.count - 20) }
        pendingSuppressedDialogsByTab[key] = entries
    }

    func armPendingUploadFileURLs(_ urls: [URL], for webView: WKWebView) {
        pendingUploadFileURLsByTab[ObjectIdentifier(webView)] = urls
    }

    var pendingUploadFileURLs: [URL]? {
        pendingUploadFileURLsByTab[ObjectIdentifier(webView)]
    }

    func pendingUploadFileURLs(for webView: WKWebView) -> [URL]? {
        pendingUploadFileURLsByTab[ObjectIdentifier(webView)]
    }

    func disarmPendingUploadFileURLs(for webView: WKWebView) {
        pendingUploadFileURLsByTab.removeValue(forKey: ObjectIdentifier(webView))
    }

    /// Consumes pending upload URLs for the given webView (open-panel delivery is
    /// one-shot per arming). Returns nil when nothing was armed for that tab.
    func consumePendingUploadFileURLs(for webView: WKWebView) -> [URL]? {
        pendingUploadFileURLsByTab.removeValue(forKey: ObjectIdentifier(webView))
    }

    // Download-started evidence drained by navigate()/click() on the originating tab,
    // mirroring the pendingPopupRedirectURL pattern so a download is reported on the
    // command that triggered it.
    var pendingDownloadStarted: String? {
        get { pendingDownloadStartedByTab[ObjectIdentifier(webView)] }
        set { pendingDownloadStartedByTab[ObjectIdentifier(webView)] = newValue }
    }

    func setPendingDownloadStarted(_ downloadID: String, for webView: WKWebView) {
        pendingDownloadStartedByTab[ObjectIdentifier(webView)] = downloadID
    }

    func pendingDownloadStarted(for webView: WKWebView) -> String? {
        let value = pendingDownloadStartedByTab[ObjectIdentifier(webView)]
        return (value?.isEmpty ?? true) ? nil : value
    }

    func clearPerTabState(for webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        networkUserScriptInstalledByTab.removeValue(forKey: key)
        networkCaptureActiveByTab.removeValue(forKey: key)
        consoleUserScriptInstalledByTab.removeValue(forKey: key)
        consoleCaptureActiveByTab.removeValue(forKey: key)
        pendingPopupRedirectURLByTab.removeValue(forKey: key)
        pendingSuppressedDialogsByTab.removeValue(forKey: key)
        pendingUploadFileURLsByTab.removeValue(forKey: key)
        pendingDownloadStartedByTab.removeValue(forKey: key)
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
        newWebView.uiDelegate = self
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
