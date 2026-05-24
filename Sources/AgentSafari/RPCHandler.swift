import AgentSafariCore
import Foundation

func structuredNetworkResult(_ result: [String: String], capturingOverride: Bool? = nil) -> JSONValue {
    let events = JSONValue.parseJSONText(result["events"] ?? "[]")
    let count = Double(Int(result["count"] ?? "0") ?? 0)
    let capturing = capturingOverride ?? (result["capturing"] == "true")
    return .object(["capturing": .bool(capturing), "events": events, "count": .number(count)])
}

@MainActor
func handle(_ request: RPCRequest, browser: BrowserController) async -> RPCResponse {
    do {
        let params = request.params ?? [:]
        let result: JSONValue
        switch request.method {
        case "navigate":
            guard let url = params["url"] else { throw AgentSafariError.missingParam("url") }
            result = JSONValue.fromStringMap(try await browser.navigate(url))
        case "evaluate":
            guard let script = params["script"] else { throw AgentSafariError.missingParam("script") }
            result = JSONValue.fromStringMap(try await browser.evaluate(script))
        case "text":
            result = JSONValue.fromStringMap(try await browser.text())
        case "html":
            result = JSONValue.fromStringMap(try await browser.html())
        case "url":
            result = JSONValue.fromStringMap(try await browser.url())
        case "title":
            result = JSONValue.fromStringMap(try await browser.title())
        case "back":
            result = JSONValue.fromStringMap(try await browser.back())
        case "forward":
            result = JSONValue.fromStringMap(try await browser.forward())
        case "reload":
            result = JSONValue.fromStringMap(try await browser.reload())
        case "viewport":
            let width = try parseNonNegativeIntParam(params, name: "width")
            let height = try parseNonNegativeIntParam(params, name: "height")
            result = JSONValue.fromStringMap(try await browser.viewport(width: width, height: height))
        case "snapshot":
            let snapshot = try await browser.snapshot()["snapshot"] ?? "[]"
            result = .object(["elements": JSONValue.parseJSONText(snapshot), "schemaVersion": .number(2)])
        case "screenshot":
            let path = params["path"] ?? "\(NSHomeDirectory())/.agent-safari/artifacts/screenshot.png"
            result = JSONValue.fromStringMap(try await browser.screenshot(path: path))
        case "screenshotFull":
            let path = params["path"] ?? "\(NSHomeDirectory())/.agent-safari/artifacts/screenshot-full.png"
            result = JSONValue.fromStringMap(try await browser.screenshotFull(path: path))
        case "screenshotElement":
            guard let selector = params["selector"] else { throw AgentSafariError.missingParam("selector") }
            let path = params["path"] ?? "\(NSHomeDirectory())/.agent-safari/artifacts/screenshot-element.png"
            result = JSONValue.fromStringMap(try await browser.screenshotElement(selector: selector, path: path))
        case "click":
            guard let selector = params["selector"] else { throw AgentSafariError.missingParam("selector") }
            result = JSONValue.fromStringMap(try await browser.click(selector: selector, native: params["native"] == "true", fallbackPolicy: params["fallback"] ?? "js"))
        case "fill":
            guard let selector = params["selector"] else { throw AgentSafariError.missingParam("selector") }
            guard let value = params["value"] else { throw AgentSafariError.missingParam("value") }
            result = JSONValue.fromStringMap(try await browser.fill(selector: selector, value: value))
        case "key":
            guard let key = params["key"] else { throw AgentSafariError.missingParam("key") }
            result = JSONValue.fromStringMap(try await browser.key(key))
        case "type":
            guard let text = params["text"] else { throw AgentSafariError.missingParam("text") }
            result = JSONValue.fromStringMap(try await browser.typeText(text))
        case "wait":
            let ms = try parseNonNegativeIntParam(params, name: "ms")
            result = JSONValue.fromStringMap(try await browser.wait(ms: ms))
        case "waitForSelector":
            guard let selector = params["selector"] else { throw AgentSafariError.missingParam("selector") }
            let timeoutMs = try parseNonNegativeIntParam(params, name: "timeoutMs", defaultValue: 10_000)
            result = JSONValue.fromStringMap(try await browser.waitForSelector(selector, timeoutMs: timeoutMs))
        case "waitForText":
            guard let text = params["text"] else { throw AgentSafariError.missingParam("text") }
            let timeoutMs = try parseNonNegativeIntParam(params, name: "timeoutMs", defaultValue: 10_000)
            result = JSONValue.fromStringMap(try await browser.waitForText(text, timeoutMs: timeoutMs))
        case "waitForIdle":
            let timeoutMs = try parseNonNegativeIntParam(params, name: "timeoutMs", defaultValue: 10_000)
            result = JSONValue.fromStringMap(try await browser.waitForIdle(timeoutMs: timeoutMs))
        case "networkStart":
            result = structuredNetworkResult(try await browser.networkStart(), capturingOverride: true)
        case "networkStop":
            result = structuredNetworkResult(try await browser.networkStop(), capturingOverride: false)
        case "networkList":
            result = structuredNetworkResult(try await browser.networkList())
        case "networkExport":
            guard let path = params["path"] else { throw AgentSafariError.missingParam("path") }
            let maxEntries = params["maxEntries"].flatMap(Int.init)
            let bodyPreviewBytes = params["bodyPreviewBytes"].flatMap(Int.init)
            result = JSONValue.fromStringMap(try await browser.networkExport(path: path, maxEntries: maxEntries, bodyPreviewBytes: bodyPreviewBytes))
        case "session":
            result = JSONValue.fromStringMap(try await browser.session())
        case "tabs":
            let tabs = try await browser.tabs()
            result = .object(["tabs": JSONValue.parseJSONText(tabs["tabs"] ?? "[]"), "activeTabId": .string(tabs["activeTabId"] ?? "")])
        case "tabNew":
            result = JSONValue.fromStringMap(try await browser.tabNew(url: params["url"]))
        case "tabSwitch":
            guard let id = params["id"] else { throw AgentSafariError.missingParam("id") }
            result = JSONValue.fromStringMap(try await browser.tabSwitch(id: id))
        case "tabClose":
            guard let id = params["id"] else { throw AgentSafariError.missingParam("id") }
            result = JSONValue.fromStringMap(try await browser.tabClose(id: id))
        case "status":
            result = JSONValue.fromStringMap(try await browser.status())
        case "observe":
            result = JSONValue.fromStringMap(try await browser.observe())
        default:
            throw AgentSafariError.unknownMethod(request.method)
        }
        return RPCResponse(id: request.id, ok: true, result: result, error: nil)
    } catch {
        return RPCResponse(
            id: request.id,
            ok: false,
            result: nil,
            error: RPCErrorPayload(code: "error", message: describeError(error))
        )
    }
}

