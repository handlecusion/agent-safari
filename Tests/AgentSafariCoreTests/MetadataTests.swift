import Testing
@testable import AgentSafariCore

@Test func metadataClientCommandsParseWithoutUnknownCommand() throws {
    let commandArguments: [String: [String]] = [
        "navigate": ["https://example.com"],
        "text": [],
        "html": [],
        "content": [],
        "url": [],
        "title": [],
        "snapshot": [],
        "evaluate": ["document.title"],
        "screenshot": ["/tmp/viewport.png"],
        "screenshot-full": ["/tmp/full.png"],
        "click": ["#submit"],
        "fill": ["#name", "Genie"],
        "key": ["Enter"],
        "type": ["hello"],
        "wait": ["100"],
        "wait-for-selector": ["#ready"],
        "wait-for-text": ["Ready"],
        "wait-for-idle": [],
        "back": [],
        "forward": [],
        "reload": [],
        "viewport": ["1280", "720"],
        "network-start": [],
        "network-list": [],
        "network-stop": [],
        "network-export": ["/tmp/network.json"],
        "session": [],
        "tabs": [],
        "tab-new": [],
        "tab-switch": ["tab-1"],
        "tab-close": ["tab-1"],
        "status": [],
        "observe": []
    ]

    #expect(Set(commandArguments.keys) == AgentSafariMetadata.clientCommands)

    for (command, arguments) in commandArguments {
        _ = try CommandRequest.parse([command] + arguments)
    }
}
