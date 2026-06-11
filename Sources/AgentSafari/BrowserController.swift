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
/// inside the command's JS evaluation, so a TaskLocal applies for the duration
/// of one command Task. Values: "accept" | "dismiss" (nil = dismiss).
enum DialogPolicy {
    @TaskLocal static var confirm: String?
}

@MainActor
final class BrowserController: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let window: NSWindow
    let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 796))
    let chromeView = NSView(frame: NSRect(x: 0, y: 720, width: 1280, height: 76))
    let tabStripView = NSView(frame: NSRect(x: 14, y: 6, width: 1216, height: 28))
    let sidebarButton = NSButton(frame: NSRect(x: 14, y: 42, width: 34, height: 28))
    let backButton = NSButton(frame: NSRect(x: 58, y: 42, width: 34, height: 28))
    let forwardButton = NSButton(frame: NSRect(x: 94, y: 42, width: 34, height: 28))
    let shareButton = NSButton(frame: NSRect(x: 1152, y: 42, width: 34, height: 28))
    let tabOverviewButton = NSButton(frame: NSRect(x: 1194, y: 42, width: 34, height: 28))
    let newTabButton = NSButton(frame: NSRect(x: 1238, y: 8, width: 28, height: 24))
    let addressField = NSTextField(frame: NSRect(x: 14, y: 8, width: 1252, height: 28))
    let webContainerView = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
    static let addressBarHeight: CGFloat = 44
    static let tabStripHeight: CGFloat = 32
    static let chromeHeight: CGFloat = addressBarHeight + tabStripHeight
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
    private var tabButtonsByID: [String: NSButton] = [:]
    private var closeButtonsByID: [String: NSButton] = [:]

    /// Resolves to the command's target tab (TabTarget TaskLocal) or the active tab.
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
            contentRect: NSRect(x: 100, y: 100, width: 1280, height: 796),
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
        updateTabStrip()
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
        // Agent-controlled browser: allow programmatic media playback so media-control
        // play() and waitForMedia(state: playing) work without a real user gesture.
        configuration.mediaTypesRequiringUserActionForPlayback = []
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
        updateTabStrip()
        window.title = tab.webView.title.map { "Agent Safari — \($0)" } ?? "Agent Safari"
    }

    func configureBrowserChrome() {
        rootView.autoresizingMask = [.width, .height]
        rootView.wantsLayer = true

        chromeView.autoresizingMask = [.width, .minYMargin]
        chromeView.wantsLayer = true
        chromeView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        configureToolbarButton(sidebarButton, title: "▣", identifier: "agent-safari-sidebar-button", action: nil)
        configureToolbarButton(backButton, title: "‹", identifier: "agent-safari-back-button", action: #selector(backButtonPressed(_:)))
        configureToolbarButton(forwardButton, title: "›", identifier: "agent-safari-forward-button", action: #selector(forwardButtonPressed(_:)))
        configureToolbarButton(shareButton, title: "⇧", identifier: "agent-safari-share-button", action: nil)
        configureToolbarButton(tabOverviewButton, title: "▢", identifier: "agent-safari-tab-overview-button", action: nil)

        tabStripView.setAccessibilityIdentifier("agent-safari-tab-strip")
        tabStripView.autoresizingMask = [.width]

        newTabButton.title = "+"
        newTabButton.bezelStyle = .texturedRounded
        newTabButton.setButtonType(.momentaryPushIn)
        newTabButton.setAccessibilityIdentifier("agent-safari-new-tab-button")
        newTabButton.target = self
        newTabButton.action = #selector(newTabButtonPressed(_:))
        newTabButton.autoresizingMask = [.minXMargin]

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
        chromeView.addSubview(sidebarButton)
        chromeView.addSubview(backButton)
        chromeView.addSubview(forwardButton)
        chromeView.addSubview(shareButton)
        chromeView.addSubview(tabOverviewButton)
        chromeView.addSubview(tabStripView)
        chromeView.addSubview(newTabButton)
        chromeView.addSubview(addressField)
        layoutBrowserChrome()
    }

    func configureToolbarButton(_ button: NSButton, title: String, identifier: String, action: Selector?) {
        button.title = title
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.setAccessibilityIdentifier(identifier)
        button.font = NSFont.systemFont(ofSize: 18, weight: .regular)
        button.target = action == nil ? nil : self
        button.action = action
    }

    func layoutBrowserChrome() {
        let bounds = rootView.bounds
        let chromeHeight = BrowserController.chromeHeight
        chromeView.frame = NSRect(x: 0, y: max(0, bounds.height - chromeHeight), width: bounds.width, height: chromeHeight)
        let newTabButtonWidth: CGFloat = 28
        let chromePadding: CGFloat = 14
        let tabButtonGap: CGFloat = 8
        sidebarButton.frame = NSRect(x: 14, y: 42, width: 34, height: 28)
        backButton.frame = NSRect(x: 62, y: 42, width: 34, height: 28)
        forwardButton.frame = NSRect(x: 98, y: 42, width: 34, height: 28)
        tabOverviewButton.frame = NSRect(x: max(170, bounds.width - 48), y: 42, width: 34, height: 28)
        shareButton.frame = NSRect(x: max(132, bounds.width - 90), y: 42, width: 34, height: 28)
        let addressLeft = max(146, bounds.width * 0.30)
        let addressRight = min(bounds.width - 104, bounds.width * 0.70)
        addressField.frame = NSRect(x: addressLeft, y: 42, width: max(220, addressRight - addressLeft), height: 28)
        tabStripView.frame = NSRect(
            x: chromePadding,
            y: 6,
            width: max(120, bounds.width - (chromePadding * 2) - newTabButtonWidth - tabButtonGap),
            height: 28
        )
        newTabButton.frame = NSRect(
            x: tabStripView.frame.maxX + tabButtonGap,
            y: 8,
            width: newTabButtonWidth,
            height: 24
        )
        webContainerView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(1, bounds.height - chromeHeight))
        webView.frame = webContainerView.bounds
        updateTabStrip()
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

    func updateTabStrip() {
        for subview in tabStripView.subviews {
            subview.removeFromSuperview()
        }
        tabButtonsByID.removeAll(keepingCapacity: true)
        closeButtonsByID.removeAll(keepingCapacity: true)

        let availableWidth = max(120, tabStripView.bounds.width)
        let segmentWidth = max(112, min(220, floor(availableWidth / CGFloat(max(1, tabsModel.count)))))
        for (index, tab) in tabsModel.enumerated() {
            let x = CGFloat(index) * segmentWidth
            let tabFrame = NSRect(x: x, y: 0, width: max(96, segmentWidth - 1), height: 28)
            let tabButton = makeTabButton(for: tab, frame: tabFrame)
            tabStripView.addSubview(tabButton)
            tabButtonsByID[tab.id] = tabButton

            let closeButton = makeTabCloseButton(for: tab, frame: NSRect(x: x + 7, y: 6, width: 16, height: 16))
            tabStripView.addSubview(closeButton)
            closeButtonsByID[tab.id] = closeButton
        }
    }

    func makeTabButton(for tab: BrowserTab, frame: NSRect) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = "   \(tabTitle(for: tab))"
        button.toolTip = tab.webView.url?.absoluteString ?? tab.id
        button.setAccessibilityIdentifier("agent-safari-tab-\(tab.id)")
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.alignment = .center
        button.lineBreakMode = .byTruncatingTail
        button.font = NSFont.systemFont(ofSize: 12)
        button.target = self
        button.action = #selector(tabButtonPressed(_:))
        button.identifier = NSUserInterfaceItemIdentifier(tab.id)
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        button.layer?.backgroundColor = tab.id == activeTabID
            ? NSColor.controlBackgroundColor.withAlphaComponent(0.96).cgColor
            : NSColor.windowBackgroundColor.withAlphaComponent(0.35).cgColor
        button.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(tab.id == activeTabID ? 0.55 : 0.25).cgColor
        button.layer?.borderWidth = 0.5
        return button
    }

    func makeTabCloseButton(for tab: BrowserTab, frame: NSRect) -> NSButton {
        let button = NSButton(frame: frame)
        button.title = "x"
        button.toolTip = "Close \(tabTitle(for: tab))"
        button.setAccessibilityIdentifier("agent-safari-close-\(tab.id)")
        button.bezelStyle = .circular
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 10)
        button.target = self
        button.action = #selector(tabCloseButtonPressed(_:))
        button.identifier = NSUserInterfaceItemIdentifier(tab.id)
        button.isHidden = tabsModel.count <= 1
        return button
    }

    func tabTitle(for tab: BrowserTab) -> String {
        let rawTitle = tab.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = tab.webView.url?.host ?? tab.id
        let title = (rawTitle?.isEmpty == false ? rawTitle : fallback) ?? tab.id
        if title.count <= 24 { return title }
        let prefix = title.prefix(21)
        return "\(prefix)..."
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

    @objc func tabButtonPressed(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        do {
            try activateTab(id: id)
        } catch {
            updateTabStrip()
        }
    }

    @objc func tabCloseButtonPressed(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        Task { @MainActor in
            _ = try? await tabClose(id: id)
        }
    }

    @objc func newTabButtonPressed(_ sender: NSButton) {
        Task { @MainActor in
            _ = try? await tabNew()
        }
    }

    @objc func backButtonPressed(_ sender: NSButton) {
        Task { @MainActor in
            _ = try? await back()
        }
    }

    @objc func forwardButtonPressed(_ sender: NSButton) {
        Task { @MainActor in
            _ = try? await forward()
        }
    }

}
