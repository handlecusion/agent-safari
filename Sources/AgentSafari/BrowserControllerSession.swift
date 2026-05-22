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
        ["sessionId": sessionID, "activeTabId": activeTabID, "profile": "default", "dataStore": "default"]
    }

    func tabs() async throws -> [String: String] {
        let tab = JSONValue.object([
            "id": .string(activeTabID),
            "active": .bool(true),
            "url": .string(webView.url?.absoluteString ?? ""),
            "title": .string(webView.title ?? "")
        ])
        let encoded = try JSONEncoder().encode([tab])
        return ["tabs": String(data: encoded, encoding: .utf8) ?? "[]", "activeTabId": activeTabID]
    }

    func tabNew() async throws -> [String: String] {
        activeTabID = "tab-1"
        return ["id": activeTabID, "created": "false", "reason": "single-webview-mvp"]
    }

    func tabSwitch(id: String) async throws -> [String: String] {
        guard id == activeTabID else { throw AgentSafariError.unknownTab(id) }
        return ["id": activeTabID, "active": "true"]
    }

    func tabClose(id: String) async throws -> [String: String] {
        guard id == activeTabID else { throw AgentSafariError.unknownTab(id) }
        return ["id": activeTabID, "closed": "false", "reason": "cannot-close-last-tab"]
    }
}
