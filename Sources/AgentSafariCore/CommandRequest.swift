import Foundation

public struct CommandRequest: Equatable {
    public static let defaultTimeoutMs = "10000"

    public let method: String
    public let params: [String: String]

    public init(method: String, params: [String: String]) {
        self.method = method
        self.params = params
    }

    public static func parse(_ args: [String]) throws -> CommandRequest {
        guard let command = args.first else {
            throw CommandRequestError.missingCommand
        }

        switch command {
        case "navigate":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("url") }
            return CommandRequest(method: "navigate", params: ["url": args[1]])
        case "text":
            return CommandRequest(method: "text", params: [:])
        case "html":
            return CommandRequest(method: "html", params: [:])
        case "snapshot":
            return CommandRequest(method: "snapshot", params: [:])
        case "evaluate":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("javascript") }
            return CommandRequest(method: "evaluate", params: ["script": args[1]])
        case "screenshot":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("path") }
            return CommandRequest(method: "screenshot", params: ["path": args[1]])
        case "screenshot-full":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("path") }
            return CommandRequest(method: "screenshotFull", params: ["path": args[1]])
        case "click":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("selector") }
            var selector: String?
            var native = false
            var fallback: String?
            for arg in args.dropFirst() {
                if arg == "--native" {
                    native = true
                } else if arg == "--no-fallback" {
                    fallback = "none"
                } else if arg == "--fallback-js" || arg == "--fallback" {
                    fallback = "js"
                } else if selector == nil {
                    selector = arg
                } else {
                    throw CommandRequestError.unknownArgument(arg)
                }
            }
            guard let selector else { throw CommandRequestError.missingArgument("selector") }
            var params = ["selector": selector]
            if native { params["native"] = "true" }
            if let fallback { params["fallback"] = fallback }
            return CommandRequest(method: "click", params: params)
        case "fill":
            guard args.count >= 3 else { throw CommandRequestError.missingArgument("selector/value") }
            return CommandRequest(method: "fill", params: ["selector": args[1], "value": args[2]])
        case "key":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("key") }
            return CommandRequest(method: "key", params: ["key": args[1]])
        case "type":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("text") }
            return CommandRequest(method: "type", params: ["text": args[1]])
        case "wait":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("ms") }
            return CommandRequest(method: "wait", params: ["ms": args[1]])
        case "wait-for-selector":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("selector") }
            var params = ["selector": args[1], "timeoutMs": Self.defaultTimeoutMs]
            if let timeoutMs = try parseTimeoutMs(args, startingAt: 2) {
                params["timeoutMs"] = timeoutMs
            }
            return CommandRequest(method: "waitForSelector", params: params)
        case "wait-for-text":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("text") }
            var params = ["text": args[1], "timeoutMs": Self.defaultTimeoutMs]
            if let timeoutMs = try parseTimeoutMs(args, startingAt: 2) {
                params["timeoutMs"] = timeoutMs
            }
            return CommandRequest(method: "waitForText", params: params)
        case "wait-for-idle":
            var params = ["timeoutMs": Self.defaultTimeoutMs]
            if let timeoutMs = try parseTimeoutMs(args, startingAt: 1) {
                params["timeoutMs"] = timeoutMs
            }
            return CommandRequest(method: "waitForIdle", params: params)
        case "network-start":
            return CommandRequest(method: "networkStart", params: [:])
        case "network-stop":
            return CommandRequest(method: "networkStop", params: [:])
        case "network-list":
            return CommandRequest(method: "networkList", params: [:])
        case "url":
            return CommandRequest(method: "url", params: [:])
        case "title":
            return CommandRequest(method: "title", params: [:])
        case "content":
            return CommandRequest(method: "text", params: [:])
        case "back":
            return CommandRequest(method: "back", params: [:])
        case "forward":
            return CommandRequest(method: "forward", params: [:])
        case "reload":
            return CommandRequest(method: "reload", params: [:])
        case "viewport":
            guard args.count >= 3 else { throw CommandRequestError.missingArgument("width/height") }
            return CommandRequest(method: "viewport", params: ["width": args[1], "height": args[2]])
        case "network-export":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("path") }
            var params = ["path": args[1]]
            var index = 2
            while index < args.count {
                let arg = args[index]
                if arg == "--body-preview-bytes" {
                    guard index + 1 < args.count else { throw CommandRequestError.missingArgument("body-preview-bytes") }
                    params["bodyPreviewBytes"] = args[index + 1]
                    index += 2
                } else if arg == "--max-entries" {
                    guard index + 1 < args.count else { throw CommandRequestError.missingArgument("max-entries") }
                    params["maxEntries"] = args[index + 1]
                    index += 2
                } else {
                    throw CommandRequestError.unknownArgument(arg)
                }
            }
            return CommandRequest(method: "networkExport", params: params)
        case "session":
            return CommandRequest(method: "session", params: [:])
        case "tabs":
            return CommandRequest(method: "tabs", params: [:])
        case "tab-new":
            return CommandRequest(method: "tabNew", params: [:])
        case "tab-switch":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("id") }
            return CommandRequest(method: "tabSwitch", params: ["id": args[1]])
        case "tab-close":
            guard args.count >= 2 else { throw CommandRequestError.missingArgument("id") }
            return CommandRequest(method: "tabClose", params: ["id": args[1]])
        case "status":
            return CommandRequest(method: "status", params: [:])
        case "observe":
            return CommandRequest(method: "observe", params: [:])
        default:
            throw CommandRequestError.unknownCommand(command)
        }
    }

    private static func parseTimeoutMs(_ args: [String], startingAt startIndex: Int) throws -> String? {
        var timeoutMs: String?
        var index = startIndex
        while index < args.count {
            let arg = args[index]
            if arg == "--timeout" || arg == "--timeout-ms" {
                guard index + 1 < args.count else { throw CommandRequestError.missingArgument("timeout") }
                timeoutMs = args[index + 1]
                index += 2
            } else {
                throw CommandRequestError.unknownArgument(arg)
            }
        }
        return timeoutMs
    }
}

public enum CommandRequestError: Error, LocalizedError, Equatable {
    case missingCommand
    case missingArgument(String)
    case unknownArgument(String)
    case unknownCommand(String)

    public var errorDescription: String? {
        switch self {
        case .missingCommand:
            return "Missing command"
        case .missingArgument(let name):
            return "Missing argument: \(name)"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        case .unknownCommand(let command):
            return "Unknown command: \(command)"
        }
    }
}
