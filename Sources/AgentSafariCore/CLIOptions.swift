import Foundation

public struct CLIOptions: Equatable {
    public static let defaultSocketPath = "/tmp/agent-safari.sock"

    public let socketPath: String
    public let focusWindow: Bool
    public let profileName: String
    public let ephemeral: Bool
    public let tabID: String?
    public let positionalArguments: [String]

    public init(socketPath: String, focusWindow: Bool = false, profileName: String = "default", ephemeral: Bool = false, tabID: String? = nil, positionalArguments: [String]) {
        self.socketPath = socketPath
        self.focusWindow = focusWindow
        self.profileName = profileName
        self.ephemeral = ephemeral
        self.tabID = tabID
        self.positionalArguments = positionalArguments
    }

    public static func parse(_ args: [String]) -> CLIOptions {
        var socketPath = defaultSocketPath
        var focusWindow = false
        var profileName = "default"
        var ephemeral = false
        var tabID: String?
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
            } else if arg == "--profile", index + 1 < args.count {
                profileName = args[index + 1]
                index += 2
            } else if arg == "--ephemeral" || arg == "--non-persistent" {
                ephemeral = true
                index += 1
            } else if arg == "--tab", index + 1 < args.count {
                tabID = args[index + 1]
                index += 2
            } else {
                positional.append(arg)
                index += 1
            }
        }

        return CLIOptions(socketPath: socketPath, focusWindow: focusWindow, profileName: profileName, ephemeral: ephemeral, tabID: tabID, positionalArguments: positional)
    }
}
