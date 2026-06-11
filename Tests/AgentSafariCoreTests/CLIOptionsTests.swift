import Testing
@testable import AgentSafariCore

@Test func cliOptionsDefaultToUnixSocket() {
    let options = CLIOptions.parse(["navigate", "https://example.com"])

    #expect(options.socketPath == "/tmp/agent-safari.sock")
    #expect(options.positionalArguments == ["navigate", "https://example.com"])
}

@Test func cliOptionsExtractSocketFlag() {
    let options = CLIOptions.parse(["navigate", "https://example.com", "--socket", "/tmp/custom.sock"])

    #expect(options.socketPath == "/tmp/custom.sock")
    #expect(options.positionalArguments == ["navigate", "https://example.com"])
}

@Test func cliOptionsDefaultDaemonDoesNotFocusWindow() {
    let options = CLIOptions.parse(["daemon"])

    #expect(options.focusWindow == false)
    #expect(options.positionalArguments == ["daemon"])
}

@Test func cliOptionsParsesFocusWindowFlag() {
    let options = CLIOptions.parse(["daemon", "--focus-window"])

    #expect(options.focusWindow == true)
    #expect(options.positionalArguments == ["daemon"])
}

@Test func cliOptionsParsesNoFocusWindowFlag() {
    let options = CLIOptions.parse(["daemon", "--focus-window", "--no-focus-window"])

    #expect(options.focusWindow == false)
    #expect(options.positionalArguments == ["daemon"])
}

@Test func cliOptionsParsesProfileAndEphemeralFlags() {
    let options = CLIOptions.parse(["daemon", "--profile", "qa", "--ephemeral"])

    #expect(options.profileName == "qa")
    #expect(options.ephemeral == true)
    #expect(options.positionalArguments == ["daemon"])
}

@Test func cliOptionsDefaultsToDefaultPersistentProfile() {
    let options = CLIOptions.parse(["daemon"])

    #expect(options.profileName == "default")
    #expect(options.ephemeral == false)
}

@Test func cliOptionsParsesTabFlag() {
    let options = CLIOptions.parse(["click", "#btn", "--tab", "tab-2"])

    #expect(options.tabID == "tab-2")
    #expect(options.positionalArguments == ["click", "#btn"])
}

@Test func cliOptionsDefaultsToNoTab() {
    let options = CLIOptions.parse(["click", "#btn"])

    #expect(options.tabID == nil)
}
