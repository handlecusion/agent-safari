import Testing
@testable import AgentSafariCore

@Test func metadataClientCommandsParseWithoutUnknownCommand() throws {
    let commandArguments: [String: [String]] = [
        "navigate": ["https://example.com"],
        "open": ["https://example.com"],
        "text": [],
        "html": [],
        "content": [],
        "url": [],
        "title": [],
        "snapshot": [],
        "evaluate": ["document.title"],
        "screenshot": ["/tmp/viewport.png"],
        "screenshot-full": ["/tmp/full.png"],
        "screenshot-element": ["#hero", "--out", "/tmp/hero.png"],
        "click": ["#submit"],
        "fill": ["#name", "Genie"],
        "upload": ["#file", "/tmp/example.txt"],
        "key": ["Enter"],
        "type": ["hello"],
        "wait": ["100"],
        "wait-for-selector": ["#ready"],
        "wait-for-text": ["Ready"],
        "wait-for-url": ["example.com"],
        "wait-for-title": ["Example"],
        "wait-for-visible": ["#ready"],
        "wait-for-idle": [],
        "back": [],
        "forward": [],
        "reload": [],
        "viewport": ["1280", "720"],
        "network-start": [],
        "network": ["list"],
        "network-list": [],
        "network-stop": [],
        "network-export": ["/tmp/network.json"],
        "console": ["list"],
        "console-start": [],
        "console-list": [],
        "console-stop": [],
        "session": [],
        "tabs": [],
        "tab-new": [],
        "tab-switch": ["tab-1"],
        "tab-close": ["tab-1"],
        "status": [],
        "observe": [],
        "media": [],
        "wait-for-media": ["#beep", "--state", "playing"],
        "media-control": ["#beep", "play"]
    ]

    #expect(Set(commandArguments.keys) == AgentSafariMetadata.clientCommands)

    for (command, arguments) in commandArguments {
        _ = try CommandRequest.parse([command] + arguments)
    }
}
