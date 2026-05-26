import Foundation

public enum AgentSafariMetadata {
    public static let version = "0.0.5"

    public static let clientCommands: Set<String> = [
        "navigate", "open", "text", "html", "content", "url", "title",
        "snapshot", "evaluate", "screenshot", "screenshot-full", "screenshot-element",
        "click", "fill", "key", "type",
        "wait", "wait-for-selector", "wait-for-text", "wait-for-idle",
        "back", "forward", "reload", "viewport",
        "network", "network-start", "network-list", "network-stop", "network-export",
        "session", "tabs", "tab-new", "tab-switch", "tab-close",
        "status", "observe"
    ]
}
