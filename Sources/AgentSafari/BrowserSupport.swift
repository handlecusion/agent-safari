import AgentSafariCore
import AppKit
import Foundation

struct ElementHitTarget {
    let viewportCenter: CGPoint
    let viewportBounds: CGRect
    let description: String
}

func stringifyJavaScriptValue(_ value: Any) -> String {
    if let optional = Mirror(reflecting: value).children.first?.value {
        return stringifyJavaScriptValue(optional)
    }
    if value is NSNull {
        return ""
    }
    return String(describing: value)
}

func javaScriptStringLiteral(_ value: String) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let literal = String(data: data, encoding: .utf8) else {
        throw AgentSafariError.javascriptEncodingFailed
    }
    return literal
}

enum BrowserUserAgentSettings {
    // Match cmux: always present as Safari. Some WKWebView builds expose a minimal
    // app WebKit user agent without Version/Safari tokens, and Google can serve
    // an unsupported-browser banner or fallback login UI in that case.
    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.2 Safari/605.1.15"
}

