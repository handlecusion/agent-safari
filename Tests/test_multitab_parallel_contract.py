#!/usr/bin/env python3
"""Regression contracts for parallel multi-tab targeting (Phase 5.5)."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "Sources" / "AgentSafari" / "BrowserController.swift"
RPC = ROOT / "Sources" / "AgentSafari" / "RPCHandler.swift"
NAVIGATION = ROOT / "Sources" / "AgentSafari" / "BrowserControllerNavigation.swift"
NAV_DELEGATE = ROOT / "Sources" / "AgentSafari" / "BrowserControllerNavigationDelegate.swift"
SESSION = ROOT / "Sources" / "AgentSafari" / "BrowserControllerSession.swift"
INPUT = ROOT / "Sources" / "AgentSafari" / "BrowserControllerInput.swift"
ERRORS = ROOT / "Sources" / "AgentSafari" / "AgentSafariError.swift"
CLI_OPTIONS = ROOT / "Sources" / "AgentSafariCore" / "CLIOptions.swift"
MAIN = ROOT / "Sources" / "AgentSafari" / "main.swift"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_task_local_tab_target_exists() -> None:
    source = read(CONTROLLER)
    assert "enum TabTarget" in source
    assert "@TaskLocal static var tabID: String?" in source
    # webView resolution must consult the task-local target before the active tab
    assert "TabTarget.tabID ?? activeTabID" in source


def test_per_tab_state_is_keyed_by_webview() -> None:
    source = read(CONTROLLER)
    assert "navigationContinuations: [ObjectIdentifier: CheckedContinuation<Void, Error>]" in source
    assert "networkUserScriptInstalledByTab" in source
    assert "networkCaptureActiveByTab" in source
    assert "pendingPopupRedirectURLByTab" in source
    # Original property names must remain as per-tab computed accessors
    assert "var networkCaptureActive: Bool" in source
    assert "var networkUserScriptInstalled: Bool" in source
    assert "var pendingPopupRedirectURL: String?" in source
    assert "func clearPerTabState(for webView: WKWebView)" in source


def test_rpc_layer_binds_validates_and_reports_tab() -> None:
    source = read(RPC)
    assert 'params["tab"]' in source
    assert "browser.hasTab(requestedTabID)" in source
    assert "TabTarget.$tabID.withValue(requestedTabID)" in source
    # Unknown tab must fail before dispatch; closure mid-command must fail after
    assert "AgentSafariError.unknownTab(requestedTabID)" in source
    assert "AgentSafariError.tabClosedDuringCommand(requestedTabID)" in source
    # Every object result reports the tab it acted on
    assert 'object["tabId"] == nil' in source
    assert "requestedTabID ?? browser.activeTabID" in source


def test_concurrent_navigation_isolation() -> None:
    nav = read(NAVIGATION)
    # Second navigate on a tab with an in-flight navigation must fail explicitly
    assert "navigationInProgress" in nav
    assert "navigationContinuations[key] == nil" in nav
    # Address bar only reflects the visible tab
    assert "target === activeTabWebView" in nav
    delegate = read(NAV_DELEGATE)
    # Delegate callbacks resolve the continuation of the webView that fired them:
    # didFinish, navigationResponse/navigationAction didBecome download, didFail, and
    # didFailProvisionalNavigation (policy-change-to-download swallow + the throwing path).
    assert delegate.count("removeValue(forKey: ObjectIdentifier(webView))") == 6


def test_tab_close_fails_inflight_navigation_and_clears_state() -> None:
    source = read(SESSION)
    assert "tabClosedDuringCommand" in source
    assert "clearPerTabState(for: closingWebView)" in source


def test_native_input_requires_active_tab() -> None:
    source = read(INPUT)
    assert "tabNotActiveForNativeInput" in source
    assert "webView === activeTabWebView" in source


def test_stable_error_codes() -> None:
    source = read(ERRORS)
    for code in (
        '"unknown_tab"',
        '"navigation_in_progress"',
        '"tab_closed_during_command"',
        '"tab_not_active_for_native_input"',
    ):
        assert code in source, f"missing stable error code {code}"


def test_cli_exposes_global_tab_option() -> None:
    options = read(CLI_OPTIONS)
    assert '"--tab"' in options
    assert "tabID: String?" in options
    main = read(MAIN)
    assert 'params["tab"] = tabID' in main


def main() -> int:
    test_task_local_tab_target_exists()
    test_per_tab_state_is_keyed_by_webview()
    test_rpc_layer_binds_validates_and_reports_tab()
    test_concurrent_navigation_isolation()
    test_tab_close_fails_inflight_navigation_and_clears_state()
    test_native_input_requires_active_tab()
    test_stable_error_codes()
    test_cli_exposes_global_tab_option()
    print("multi-tab parallel contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
