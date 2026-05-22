import AgentSafariCore
import Darwin
import Foundation

func printDoctor(socketPath: String) {
    let binary = CommandLine.arguments.first ?? "agent-safari"
    let socketExists = FileManager.default.fileExists(atPath: socketPath)
    var daemonReachable = false
    if let fd = try? connectClient(socketPath: socketPath) {
        daemonReachable = true
        close(fd)
    }
    let payload: JSONValue = .object([
        "version": .string(AgentSafariMetadata.version),
        "binary": .string(binary),
        "socketPath": .string(socketPath),
        "socketExists": .bool(socketExists),
        "daemonReachable": .bool(daemonReachable),
        "platform": .string("macOS"),
        "webkit": .bool(true)
    ])
    let data = (try? JSONEncoder().encode(payload)) ?? Data()
    print(String(data: data, encoding: .utf8) ?? "{}")
}

func usage() {
    print("""
    agent-safari --version
    agent-safari doctor [--socket /tmp/agent-safari.sock]
    agent-safari daemon [--focus-window] [--socket /tmp/agent-safari.sock]
    agent-safari navigate <url> [--socket /tmp/agent-safari.sock]
    agent-safari text|content|html|url|title [--socket /tmp/agent-safari.sock]
    agent-safari snapshot [--socket /tmp/agent-safari.sock]
    agent-safari evaluate <javascript> [--socket /tmp/agent-safari.sock]
    agent-safari screenshot <path> [--socket /tmp/agent-safari.sock]
    agent-safari screenshot-full <path> [--socket /tmp/agent-safari.sock]
    agent-safari click <selector> [--native] [--no-fallback] [--socket /tmp/agent-safari.sock]
    agent-safari fill <selector> <value> [--socket /tmp/agent-safari.sock]
    agent-safari key <key> [--socket /tmp/agent-safari.sock]
    agent-safari type <text> [--socket /tmp/agent-safari.sock]
    agent-safari wait <ms> [--socket /tmp/agent-safari.sock]
    agent-safari wait-for-selector <selector> [--timeout <ms>] [--socket /tmp/agent-safari.sock]
    agent-safari wait-for-text <text> [--timeout <ms>] [--socket /tmp/agent-safari.sock]
    agent-safari wait-for-idle [--timeout <ms>] [--socket /tmp/agent-safari.sock]
    agent-safari back|forward|reload [--socket /tmp/agent-safari.sock]
    agent-safari viewport <width> <height> [--socket /tmp/agent-safari.sock]
    agent-safari network-start|network-list|network-stop [--socket /tmp/agent-safari.sock]
    agent-safari network-export <path> [--body-preview-bytes N] [--max-entries N] [--socket /tmp/agent-safari.sock]
    agent-safari session|tabs|tab-new [--socket /tmp/agent-safari.sock]
    agent-safari tab-switch <id> [--socket /tmp/agent-safari.sock]
    agent-safari tab-close <id> [--socket /tmp/agent-safari.sock]
    agent-safari status|observe [--socket /tmp/agent-safari.sock]
    """)
}

