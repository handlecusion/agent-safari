import Foundation

public struct CLIOptions: Equatable {
    public static let defaultSocketPath = "/tmp/agent-safari.sock"

    public let socketPath: String
    public let focusWindow: Bool
    public let positionalArguments: [String]

    public init(socketPath: String, focusWindow: Bool = false, positionalArguments: [String]) {
        self.socketPath = socketPath
        self.focusWindow = focusWindow
        self.positionalArguments = positionalArguments
    }

    public static func parse(_ args: [String]) -> CLIOptions {
        var socketPath = defaultSocketPath
        var focusWindow = false
        var positional: [String] = []
        var index = 0

        while index < args.count {
            let arg = args[index]
            if arg == "--socket", index + 1 < args.count {
                socketPath = args[index + 1]
                index += 2
            } else if arg == "--focus-window" {
                focusWindow = true
                index += 1
            } else if arg == "--no-focus-window" {
                focusWindow = false
                index += 1
            } else {
                positional.append(arg)
                index += 1
            }
        }

        return CLIOptions(socketPath: socketPath, focusWindow: focusWindow, positionalArguments: positional)
    }
}
