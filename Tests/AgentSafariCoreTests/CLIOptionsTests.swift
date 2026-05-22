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
