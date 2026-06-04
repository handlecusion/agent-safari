import Foundation

enum AgentSafariError: Error, LocalizedError {
    case invalidURL(String)
    case missingParam(String)
    case screenshotFailed
    case pageMeasurementFailed
    case javascriptEncodingFailed
    case invalidIntegerParam(String, String)
    case waitTimedOut(Int)
    case elementResolutionFailed(String)
    case nativeInputFailed(String)
    case unknownMethod(String)
    case unknownTab(String)
    case socketPathTooLong(String)
    case socketOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value): return "Invalid URL: \(value)"
        case .missingParam(let name): return "Missing param: \(name)"
        case .screenshotFailed: return "Failed to encode screenshot as PNG"
        case .pageMeasurementFailed: return "Failed to measure page dimensions"
        case .javascriptEncodingFailed: return "Failed to encode JavaScript string literal"
        case .invalidIntegerParam(let name, let value): return "Invalid integer for \(name): \(value)"
        case .waitTimedOut(let timeoutMs): return "Timed out after \(timeoutMs) ms"
        case .elementResolutionFailed(let target): return "Failed to resolve clickable element: \(target)"
        case .nativeInputFailed(let message): return "Native input failed: \(message)"
        case .unknownMethod(let method): return "Unknown method: \(method)"
        case .unknownTab(let id): return "Unknown tab id: \(id)"
        case .socketPathTooLong(let path): return "Unix socket path is too long: \(path)"
        case .socketOperationFailed(let message): return message
        }
    }
}

func describeError(_ error: Error) -> String {
    let nsError = error as NSError
    if let message = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String {
        let line = nsError.userInfo["WKJavaScriptExceptionLineNumber"].map { String(describing: $0) } ?? "?"
        return "JavaScript exception at line \(line): \(message)"
    }
    return error.localizedDescription
}

func agentSafariErrorCode(_ error: Error) -> String {
    agentSafariErrorCode(describeError(error))
}

func agentSafariErrorCode(_ message: String) -> String {
    if message.contains("No element found for snapshot ref:") {
        return "actionability_stale_ref"
    }
    if message.contains("Snapshot refs are not available") {
        return "actionability_refs_unavailable"
    }
    if message.contains("No element found for selector:") {
        return "actionability_missing_selector"
    }
    if message.contains("Element is disabled:") {
        return "actionability_disabled"
    }
    if message.contains("Element is hidden:") {
        return "actionability_hidden"
    }
    if message.contains("Element center is outside viewport:")
        || message.contains("Failed to resolve clickable element: offscreen center") {
        return "actionability_off_viewport"
    }
    if message.contains("Element center is occluded:") {
        return "actionability_occluded"
    }
    if message.contains("Native Quartz click posted but no DOM click event was observed") {
        return "native_click_unverified"
    }
    if message.contains("Native input failed:") || message.contains("Failed to create native mouse events") {
        return "native_input_failed"
    }
    return "error"
}

func parseNonNegativeIntParam(_ params: [String: String], name: String, defaultValue: Int? = nil) throws -> Int {
    guard let value = params[name] else {
        if let defaultValue { return defaultValue }
        throw AgentSafariError.missingParam(name)
    }
    guard let intValue = Int(value), intValue >= 0 else {
        throw AgentSafariError.invalidIntegerParam(name, value)
    }
    return intValue
}
