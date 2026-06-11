import Foundation

public enum AgentSafariMetadata {
    public static let version = "0.0.7"

    public static let clientCommands: Set<String> = [
        "navigate", "open", "text", "html", "content", "url", "title",
        "snapshot", "evaluate", "screenshot", "screenshot-full", "screenshot-element",
        "click", "fill", "upload", "key", "type",
        "wait", "wait-for-selector", "wait-for-text", "wait-for-url", "wait-for-title", "wait-for-visible", "wait-for-idle",
        "back", "forward", "reload", "viewport",
        "network", "network-start", "network-list", "network-stop", "network-export",
        "console", "console-start", "console-list", "console-stop",
        "session", "tabs", "tab-new", "tab-switch", "tab-close",
        "status", "observe"
    ]
}
