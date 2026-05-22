import Testing
@testable import AgentSafariCore

@Test func commandRequestParsesClickSelector() throws {
    let command = try CommandRequest.parse(["click", "#submit"])

    #expect(command.method == "click")
    #expect(command.params == ["selector": "#submit"])
}

@Test func commandRequestParsesFillSelectorAndValue() throws {
    let command = try CommandRequest.parse(["fill", "input[name=email]", "ceo@example.com"])

    #expect(command.method == "fill")
    #expect(command.params == ["selector": "input[name=email]", "value": "ceo@example.com"])
}

@Test func commandRequestParsesClickRefAsSelector() throws {
    let command = try CommandRequest.parse(["click", "@e1"])

    #expect(command.method == "click")
    #expect(command.params == ["selector": "@e1"])
}

@Test func commandRequestParsesClickNativeFlagAfterSelector() throws {
    let command = try CommandRequest.parse(["click", "#submit", "--native"])

    #expect(command.method == "click")
    #expect(command.params == ["selector": "#submit", "native": "true"])
}

@Test func commandRequestParsesClickNativeFlagBeforeSelector() throws {
    let command = try CommandRequest.parse(["click", "--native", "@e1"])

    #expect(command.method == "click")
    #expect(command.params == ["selector": "@e1", "native": "true"])
}

@Test func commandRequestParsesFillRefAsSelector() throws {
    let command = try CommandRequest.parse(["fill", "@e2", "Genie"])

    #expect(command.method == "fill")
    #expect(command.params == ["selector": "@e2", "value": "Genie"])
}

@Test func commandRequestParsesKeyValue() throws {
    let command = try CommandRequest.parse(["key", "Enter"])

    #expect(command.method == "key")
    #expect(command.params == ["key": "Enter"])
}

@Test func commandRequestParsesTypeText() throws {
    let command = try CommandRequest.parse(["type", "hello world"])

    #expect(command.method == "type")
    #expect(command.params == ["text": "hello world"])
}

@Test func commandRequestParsesWaitMilliseconds() throws {
    let command = try CommandRequest.parse(["wait", "250"])

    #expect(command.method == "wait")
    #expect(command.params == ["ms": "250"])
}

@Test func commandRequestParsesWaitForSelectorWithDefaultTimeout() throws {
    let command = try CommandRequest.parse(["wait-for-selector", "#ready"])

    #expect(command.method == "waitForSelector")
    #expect(command.params == ["selector": "#ready", "timeoutMs": "10000"])
}

@Test func commandRequestParsesWaitForSelectorWithTimeout() throws {
    let command = try CommandRequest.parse(["wait-for-selector", "#ready", "--timeout", "1500"])

    #expect(command.method == "waitForSelector")
    #expect(command.params == ["selector": "#ready", "timeoutMs": "1500"])
}

@Test func commandRequestParsesWaitForTextWithTimeoutMsAlias() throws {
    let command = try CommandRequest.parse(["wait-for-text", "Loaded", "--timeout-ms", "2000"])

    #expect(command.method == "waitForText")
    #expect(command.params == ["text": "Loaded", "timeoutMs": "2000"])
}

@Test func commandRequestParsesWaitForIdleWithDefaultTimeout() throws {
    let command = try CommandRequest.parse(["wait-for-idle"])

    #expect(command.method == "waitForIdle")
    #expect(command.params == ["timeoutMs": "10000"])
}

@Test func commandRequestParsesWaitForIdleWithTimeout() throws {
    let command = try CommandRequest.parse(["wait-for-idle", "--timeout", "3000"])

    #expect(command.method == "waitForIdle")
    #expect(command.params == ["timeoutMs": "3000"])
}

@Test func commandRequestParsesSnapshot() throws {
    let command = try CommandRequest.parse(["snapshot"])

    #expect(command.method == "snapshot")
    #expect(command.params == [:])
}

@Test func commandRequestParsesScreenshotFullPath() throws {
    let command = try CommandRequest.parse(["screenshot-full", "/tmp/full-page.png"])

    #expect(command.method == "screenshotFull")
    #expect(command.params == ["path": "/tmp/full-page.png"])
}

@Test func commandRequestParsesNetworkStart() throws {
    let command = try CommandRequest.parse(["network-start"])

    #expect(command.method == "networkStart")
    #expect(command.params == [:])
}

@Test func commandRequestParsesNetworkStop() throws {
    let command = try CommandRequest.parse(["network-stop"])

    #expect(command.method == "networkStop")
    #expect(command.params == [:])
}

@Test func commandRequestParsesNetworkList() throws {
    let command = try CommandRequest.parse(["network-list"])

    #expect(command.method == "networkList")
    #expect(command.params == [:])
}

@Test func commandRequestParsesStatus() throws {
    let command = try CommandRequest.parse(["status"])

    #expect(command.method == "status")
    #expect(command.params == [:])
}

@Test func commandRequestParsesObserve() throws {
    let command = try CommandRequest.parse(["observe"])

    #expect(command.method == "observe")
    #expect(command.params == [:])
}

@Test func commandRequestParsesUrlTitleAndContentAliases() throws {
    #expect(try CommandRequest.parse(["url"]).method == "url")
    #expect(try CommandRequest.parse(["title"]).method == "title")
    #expect(try CommandRequest.parse(["content"]).method == "text")
}

@Test func commandRequestParsesHistoryAndViewport() throws {
    #expect(try CommandRequest.parse(["back"]).method == "back")
    #expect(try CommandRequest.parse(["forward"]).method == "forward")
    #expect(try CommandRequest.parse(["reload"]).method == "reload")
    let viewport = try CommandRequest.parse(["viewport", "1024", "768"])
    #expect(viewport.method == "viewport")
    #expect(viewport.params == ["width": "1024", "height": "768"])
}

@Test func commandRequestParsesNetworkExportAndNativeFallbackPolicy() throws {
    let click = try CommandRequest.parse(["click", "#submit", "--native", "--no-fallback"])
    #expect(click.params["fallback"] == "none")
    let export = try CommandRequest.parse(["network-export", "/tmp/network.json", "--body-preview-bytes", "128", "--max-entries", "10"])
    #expect(export.method == "networkExport")
    #expect(export.params["path"] == "/tmp/network.json")
    #expect(export.params["bodyPreviewBytes"] == "128")
    #expect(export.params["maxEntries"] == "10")
}

@Test func commandRequestParsesSessionAndTabCommands() throws {
    #expect(try CommandRequest.parse(["session"]).method == "session")
    #expect(try CommandRequest.parse(["tabs"]).method == "tabs")
    #expect(try CommandRequest.parse(["tab-new"]).method == "tabNew")
    #expect(try CommandRequest.parse(["tab-switch", "tab-1"]).params == ["id": "tab-1"])
    #expect(try CommandRequest.parse(["tab-close", "tab-1"]).params == ["id": "tab-1"])
}
