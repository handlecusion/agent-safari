#!/usr/bin/env python3
"""Contract checks for Phase 5 modeled session/tab/profile semantics."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "Sources" / "AgentSafari" / "BrowserController.swift"
SESSION = ROOT / "Sources" / "AgentSafari" / "BrowserControllerSession.swift"
MCP = ROOT / "mcp" / "agent_safari_mcp.py"
PRODUCT_SPEC = ROOT / "docs" / "PRODUCT_SPEC.md"
DEVELOPMENT_PHASES = ROOT / "docs" / "DEVELOPMENT_PHASES.md"
PROFILE_PERSISTENCE = ROOT / "docs" / "PROFILE_PERSISTENCE.md"
README = ROOT / "README.md"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_modeled_tabs_are_webkit_backed_inside_one_daemon_window() -> None:
    controller = read(CONTROLLER)
    session = read(SESSION)

    assert "struct BrowserTab" in controller
    assert "let webView: WKWebView" in controller
    assert "var tabsModel: [BrowserTab] = []" in controller
    assert "activeTabID" in controller
    assert "attachWebViewToContainer" in controller
    assert "window.title = \"Agent Safari\"" in controller
    assert "tabsModel.append(BrowserTab" in session
    assert "try activateTab(id: id)" in session
    assert "cannot-close-last-tab" in session
    assert '"activeTabId": activeTabID' in session
    assert '"reason": ""' in session


def test_session_reports_profile_persistence_and_tab_count_fields() -> None:
    controller = read(CONTROLLER)
    session = read(SESSION)

    assert "configuration.websiteDataStore = ephemeral ? .nonPersistent() : .default()" in controller
    for field in ('"sessionId"', '"activeTabId"', '"profile"', '"persistent"', '"dataStore"', '"tabCount"'):
        assert field in session, f"missing session result field {field}"
    assert '"dataStore": ephemeral ? "nonPersistent" : "default"' in session
    assert '"tabCount": String(tabsModel.count)' in session


def test_mcp_contract_advertises_full_phase5_result_shape() -> None:
    namespace: dict[str, object] = {}
    exec(MCP.read_text(encoding="utf-8"), namespace)
    tool_contracts = namespace["TOOL_CONTRACTS"]
    assert isinstance(tool_contracts, list)
    contracts = {tool["name"]: tool for tool in tool_contracts}

    assert contracts["status"]["result"] == ["url", "title", "loading", "sessionId", "tabId"]
    assert contracts["session"]["result"] == ["sessionId", "activeTabId", "profile", "persistent", "dataStore", "tabCount"]
    assert contracts["tabs"]["result"] == ["tabs", "activeTabId"]
    assert contracts["tab_new"]["result"] == ["id", "tabId", "created", "url", "title"]
    assert contracts["tab_switch"]["result"] == ["id", "tabId", "active", "url", "title"]
    assert contracts["tab_close"]["result"] == ["id", "tabId", "closed", "activeTabId", "reason"]
    assert contracts["tab_switch"]["input"] == ["tab_id"]
    assert contracts["tab_close"]["input"] == ["tab_id"]


def test_phase5_docs_state_current_scope_without_isolation_overclaim() -> None:
    combined = "\n".join(
        read(path)
        for path in (PRODUCT_SPEC, DEVELOPMENT_PHASES, PROFILE_PERSISTENCE, README)
    )
    required_phrases = [
        "modeled tab",
        "one daemon",
        "one native WebKit window",
        "WKWebsiteDataStore.default()",
        "WKWebsiteDataStore.nonPersistent()",
        "AGENT_SAFARI_SOCKET",
        "separate daemon",
        "caller-owned output paths",
        "Named per-profile stores are not implemented",
        "not a true browser multi-target",
    ]
    for phrase in required_phrases:
        assert phrase.lower() in combined.lower(), f"missing Phase 5 scope phrase {phrase!r}"


def main() -> int:
    test_modeled_tabs_are_webkit_backed_inside_one_daemon_window()
    test_session_reports_profile_persistence_and_tab_count_fields()
    test_mcp_contract_advertises_full_phase5_result_shape()
    test_phase5_docs_state_current_scope_without_isolation_overclaim()
    print("session/profile contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
