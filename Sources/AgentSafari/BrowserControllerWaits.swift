import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    func wait(ms: Int) async throws -> [String: String] {
        let clampedMs = min(max(0, ms), 86_400_000)
        try await Task.sleep(nanoseconds: UInt64(clampedMs) * 1_000_000)
        return ["waitedMs": String(clampedMs)]
    }

    func waitForSelector(_ selector: String, timeoutMs: Int) async throws -> [String: String] {
        let selectorLiteral = try javaScriptStringLiteral(selector)
        let script = "document.querySelector(\(selectorLiteral)) !== null"
        try await waitUntil(timeoutMs: timeoutMs) {
            let value = try await self.webView.evaluateJavaScript(script)
            return (value as? Bool) == true
        }
        return ["selector": selector, "found": "true", "timeoutMs": String(max(0, timeoutMs))]
    }

    func waitForText(_ text: String, timeoutMs: Int) async throws -> [String: String] {
        let textLiteral = try javaScriptStringLiteral(text)
        let script = "(document.body ? document.body.innerText : '').includes(\(textLiteral))"
        try await waitUntil(timeoutMs: timeoutMs) {
            let value = try await self.webView.evaluateJavaScript(script)
            return (value as? Bool) == true
        }
        return ["text": text, "found": "true", "timeoutMs": String(max(0, timeoutMs))]
    }

    func waitForIdle(timeoutMs: Int) async throws -> [String: String] {
        let quietWindowMs = 500
        var idleSince: Date?
        try await waitUntil(timeoutMs: timeoutMs) {
            let readyStateValue = try await self.webView.evaluateJavaScript("document.readyState")
            let pendingValue = try await self.webView.evaluateJavaScript("window.__agentSafariNetworkPending || 0")
            let readyState = stringifyJavaScriptValue(readyStateValue as Any)
            let pending = (pendingValue as? NSNumber)?.intValue ?? 0
            let currentlyIdle = !self.webView.isLoading && readyState == "complete" && pending == 0

            if currentlyIdle {
                let now = Date()
                if let since = idleSince, now.timeIntervalSince(since) * 1000 >= Double(quietWindowMs) {
                    return true
                }
                if idleSince == nil {
                    idleSince = now
                }
            } else {
                idleSince = nil
            }
            return false
        }
        return ["idle": "true", "timeoutMs": String(max(0, timeoutMs)), "quietWindowMs": String(quietWindowMs)]
    }

    private func waitUntil(timeoutMs: Int, condition: () async throws -> Bool) async throws {
        let clampedTimeoutMs = max(0, timeoutMs)
        let deadline = Date().addingTimeInterval(Double(clampedTimeoutMs) / 1000.0)
        repeat {
            if try await condition() {
                return
            }
            if Date() >= deadline {
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while true
        throw AgentSafariError.waitTimedOut(clampedTimeoutMs)
    }
}
