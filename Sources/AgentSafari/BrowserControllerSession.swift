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
            "tabId": TabTarget.tabID ?? activeTabID
        ]
    }

    func observe() async throws -> [String: String] {
        let script = """
        (() => {
          const active = document.activeElement;
          const selectorFor = (element) => {
            if (!element || element === document.body || element === document.documentElement) return '';
            if (element.id) return '#' + CSS.escape(element.id);
            const tag = (element.tagName || '').toLowerCase();
            if (!tag) return '';
            const name = element.getAttribute && element.getAttribute('name');
            if (name) return `${tag}[name="${CSS.escape(name)}"]`;
            return tag;
          };
          const de = document.documentElement;
          const b = document.body;
          const viewportWidth = window.innerWidth || (de ? de.clientWidth : 0) || 0;
          const viewportHeight = window.innerHeight || (de ? de.clientHeight : 0) || 0;
          const pageWidth = Math.max(
            de ? de.scrollWidth : 0,
            de ? de.offsetWidth : 0,
            de ? de.clientWidth : 0,
            b ? b.scrollWidth : 0,
            b ? b.offsetWidth : 0,
            b ? b.clientWidth : 0,
            viewportWidth
          );
          const pageHeight = Math.max(
            de ? de.scrollHeight : 0,
            de ? de.offsetHeight : 0,
            de ? de.clientHeight : 0,
            b ? b.scrollHeight : 0,
            b ? b.offsetHeight : 0,
            b ? b.clientHeight : 0,
            viewportHeight
          );
          let selectedText = '';
          try { selectedText = String(window.getSelection ? window.getSelection() : ''); } catch (_) {}
          return {
            readyState: document.readyState || '',
            loadState: document.readyState || '',
            pendingNetworkCount: window.__agentSafariNetworkPending || 0,
            selectedText,
            viewportWidth,
            viewportHeight,
            pageWidth,
            pageHeight,
            activeElementTag: active && active.tagName ? active.tagName.toLowerCase() : '',
            activeElementType: active && active.getAttribute ? (active.getAttribute('type') || '') : '',
            activeElementName: active && active.getAttribute ? (active.getAttribute('name') || '') : '',
            activeElementId: active && active.id ? active.id : '',
            activeElementSelector: selectorFor(active)
          };
        })()
        """
        let pageState = try await webView.evaluateJavaScript(script) as? [String: Any]
        return [
            "url": webView.url?.absoluteString ?? "",
            "title": webView.title ?? "",
            "readyState": stringifyJavaScriptValue((pageState?["readyState"] ?? "") as Any),
            "loadState": stringifyJavaScriptValue((pageState?["loadState"] ?? "") as Any),
            "isLoading": webView.isLoading ? "true" : "false",
            "networkCapturing": networkCaptureActive ? "true" : "false",
            "consoleCapturing": consoleCaptureActive ? "true" : "false",
            "pendingNetworkCount": stringifyJavaScriptValue((pageState?["pendingNetworkCount"] ?? 0) as Any),
            "selectedText": stringifyJavaScriptValue((pageState?["selectedText"] ?? "") as Any),
            "viewportWidth": stringifyJavaScriptValue((pageState?["viewportWidth"] ?? 0) as Any),
            "viewportHeight": stringifyJavaScriptValue((pageState?["viewportHeight"] ?? 0) as Any),
            "pageWidth": stringifyJavaScriptValue((pageState?["pageWidth"] ?? 0) as Any),
            "pageHeight": stringifyJavaScriptValue((pageState?["pageHeight"] ?? 0) as Any),
            "activeElementTag": stringifyJavaScriptValue((pageState?["activeElementTag"] ?? "") as Any),
            "activeElementType": stringifyJavaScriptValue((pageState?["activeElementType"] ?? "") as Any),
            "activeElementName": stringifyJavaScriptValue((pageState?["activeElementName"] ?? "") as Any),
            "activeElementId": stringifyJavaScriptValue((pageState?["activeElementId"] ?? "") as Any),
            "activeElementSelector": stringifyJavaScriptValue((pageState?["activeElementSelector"] ?? "") as Any),
            "sessionId": sessionID,
            "tabId": TabTarget.tabID ?? activeTabID
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
        if let url, !url.isEmpty {
            _ = try await navigate(url, in: newWebView)
        }
        return ["id": id, "tabId": id, "created": "true", "url": newWebView.url?.absoluteString ?? "", "title": newWebView.title ?? ""]
    }

    func tabSwitch(id: String) async throws -> [String: String] {
        try activateTab(id: id)
        return ["id": activeTabID, "tabId": activeTabID, "active": "true", "url": activeTabWebView.url?.absoluteString ?? "", "title": activeTabWebView.title ?? ""]
    }

    func tabClose(id: String) async throws -> [String: String] {
        guard let index = tabsModel.firstIndex(where: { $0.id == id }) else { throw AgentSafariError.unknownTab(id) }
        guard tabsModel.count > 1 else {
            return ["id": activeTabID, "tabId": activeTabID, "closed": "false", "activeTabId": activeTabID, "reason": "cannot-close-last-tab"]
        }
        let closingWebView = tabsModel[index].webView
        navigationContinuations.removeValue(forKey: ObjectIdentifier(closingWebView))?
            .resume(throwing: AgentSafariError.tabClosedDuringCommand(id))
        clearPerTabState(for: closingWebView)
        tabsModel.remove(at: index)
        if activeTabID == id {
            let replacement = tabsModel[min(index, tabsModel.count - 1)].id
            try activateTab(id: replacement)
        }
        return ["id": id, "tabId": activeTabID, "closed": "true", "activeTabId": activeTabID, "reason": ""]
    }
}
