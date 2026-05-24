import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    func status() async throws -> [String: String] {
        return [
            "url": webView.url?.absoluteString ?? "",
            "title": webView.title ?? "",
            "loading": webView.isLoading ? "true" : "false",
            "sessionId": sessionID,
            "tabId": activeTabID
        ]
    }

    func observe() async throws -> [String: String] {
        let script = """
        (() => {
          const active = document.activeElement;
          return {
            readyState: document.readyState || '',
            activeElementTag: active && active.tagName ? active.tagName.toLowerCase() : '',
            activeElementType: active && active.getAttribute ? (active.getAttribute('type') || '') : '',
            activeElementName: active && active.getAttribute ? (active.getAttribute('name') || '') : '',
            activeElementId: active && active.id ? active.id : ''
          };
        })()
        """
        let pageState = try await webView.evaluateJavaScript(script) as? [String: Any]
        return [
            "url": webView.url?.absoluteString ?? "",
            "title": webView.title ?? "",
            "readyState": stringifyJavaScriptValue((pageState?["readyState"] ?? "") as Any),
            "isLoading": webView.isLoading ? "true" : "false",
            "networkCapturing": networkCaptureActive ? "true" : "false",
            "activeElementTag": stringifyJavaScriptValue((pageState?["activeElementTag"] ?? "") as Any),
            "activeElementType": stringifyJavaScriptValue((pageState?["activeElementType"] ?? "") as Any),
            "activeElementName": stringifyJavaScriptValue((pageState?["activeElementName"] ?? "") as Any),
            "activeElementId": stringifyJavaScriptValue((pageState?["activeElementId"] ?? "") as Any),
            "sessionId": sessionID,
            "tabId": activeTabID
        ]
    }

    func session() async throws -> [String: String] {
        [
            "sessionId": sessionID,
            "activeTabId": activeTabID,
            "profile": profileName,
            "persistent": ephemeral ? "false" : "true",
            "dataStore": ephemeral ? "nonPersistent" : "default",
            "tabCount": String(tabsModel.count)
        ]
    }

    func tabs() async throws -> [String: String] {
        let tabs = tabsModel.map { tab in
            JSONValue.object([
                "id": .string(tab.id),
                "active": .bool(tab.id == activeTabID),
                "url": .string(tab.webView.url?.absoluteString ?? ""),
                "title": .string(tab.webView.title ?? ""),
                "loading": .bool(tab.webView.isLoading)
            ])
        }
        let encoded = try JSONEncoder().encode(tabs)
        return ["tabs": String(data: encoded, encoding: .utf8) ?? "[]", "activeTabId": activeTabID]
    }

    func tabNew(url: String? = nil) async throws -> [String: String] {
        let numericSuffix = (tabsModel.compactMap { Int($0.id.replacingOccurrences(of: "tab-", with: "")) }.max() ?? 0) + 1
        let id = "tab-\(numericSuffix)"
        let newWebView = makeWebView()
        tabsModel.append(BrowserTab(id: id, webView: newWebView, createdAt: Date()))
        try activateTab(id: id)
        networkUserScriptInstalled = false
        networkCaptureActive = false
        if let url, !url.isEmpty {
            _ = try await navigate(url)
        }
        return ["id": id, "tabId": id, "created": "true", "url": webView.url?.absoluteString ?? "", "title": webView.title ?? ""]
    }

    func tabSwitch(id: String) async throws -> [String: String] {
        try activateTab(id: id)
        networkUserScriptInstalled = false
        networkCaptureActive = false
        return ["id": activeTabID, "tabId": activeTabID, "active": "true", "url": webView.url?.absoluteString ?? "", "title": webView.title ?? ""]
    }

    func tabClose(id: String) async throws -> [String: String] {
        guard let index = tabsModel.firstIndex(where: { $0.id == id }) else { throw AgentSafariError.unknownTab(id) }
        guard tabsModel.count > 1 else {
            return ["id": activeTabID, "tabId": activeTabID, "closed": "false", "reason": "cannot-close-last-tab"]
        }
        tabsModel.remove(at: index)
        if activeTabID == id {
            let replacement = tabsModel[min(index, tabsModel.count - 1)].id
            try activateTab(id: replacement)
        }
        return ["id": id, "tabId": activeTabID, "closed": "true", "activeTabId": activeTabID]
    }
}
