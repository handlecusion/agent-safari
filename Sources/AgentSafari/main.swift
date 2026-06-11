import AgentSafariCore
import AppKit
import Darwin
import Foundation

let options = CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
let args = options.positionalArguments

if args.first == "--version" || args.first == "version" {
    print(AgentSafariMetadata.version)
} else if args.first == "doctor" {
    printDoctor(socketPath: options.socketPath)
} else if args.first == "daemon" {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let browser = BrowserController(focusWindow: options.focusWindow, profileName: options.profileName, ephemeral: options.ephemeral)
    let server = UnixSocketServer(path: options.socketPath, browser: browser)
    try server.start()
    app.run()
} else if AgentSafariMetadata.clientCommands.contains(args.first ?? "") {
    do {
        let command = try CommandRequest.parse(args)
        var params = command.params
        if let tabID = options.tabID { params["tab"] = tabID }
        try sendClient(method: command.method, params: params, socketPath: options.socketPath)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        usage()
        exit(1)
    }
} else {
    usage()
}
