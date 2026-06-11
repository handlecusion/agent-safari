#!/usr/bin/env python3
"""Regression contracts for JS dialog (alert/confirm/prompt) evidence and the
per-command confirm policy."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT / "Sources" / "AgentSafari" / "BrowserController.swift"
UI_DELEGATE = ROOT / "Sources" / "AgentSafari" / "BrowserControllerUIDelegate.swift"
INPUT = ROOT / "Sources" / "AgentSafari" / "BrowserControllerInput.swift"
SESSION = ROOT / "Sources" / "AgentSafari" / "BrowserControllerSession.swift"
RPC = ROOT / "Sources" / "AgentSafari" / "RPCHandler.swift"
CLI_OPTIONS = ROOT / "Sources" / "AgentSafariCore" / "CLIOptions.swift"
MAIN = ROOT / "Sources" / "AgentSafari" / "main.swift"
MCP = ROOT / "mcp" / "agent_safari_mcp.py"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_per_tab_dialog_buffer_mirrors_popup_shape() -> None:
    source = read(CONTROLLER)
    # Per-tab storage keyed by ObjectIdentifier, same shape as popup redirect.
    assert "pendingSuppressedDialogsByTab: [ObjectIdentifier: [String]]" in source
    # Computed accessor resolves through `webView` (task-local aware) like the popup one.
    assert "var pendingSuppressedDialogs: [String]" in source
    assert "pendingSuppressedDialogsByTab[ObjectIdentifier(webView)]" in source
    # Explicit setter takes the delegate's webView, mirroring setPendingPopupRedirectURL.
    assert "func appendSuppressedDialog(_ entry: String, for webView: WKWebView)" in source
    # Buffer capped at 20 entries (drop oldest).
    assert "> 20" in source
    assert "removeFirst" in source
    # Cleared alongside the other per-tab state.
    assert "pendingSuppressedDialogsByTab.removeValue(forKey: key)" in source


def test_dialog_policy_task_local_exists() -> None:
    source = read(CONTROLLER)
    assert "enum DialogPolicy" in source
    assert "@TaskLocal static var confirm: String?" in source


def test_ui_delegate_records_dialog_evidence() -> None:
    source = read(UI_DELEGATE)
    # alert records "alert: <message>" via the delegate's webView.
    assert 'appendSuppressedDialog("alert: \\(message)", for: webView)' in source
    # confirm records both policy outcomes.
    assert 'appendSuppressedDialog("confirm(false): \\(message)", for: webView)' in source
    assert 'appendSuppressedDialog("confirm(true): \\(message)", for: webView)' in source
    # prompt records 'prompt(""): <prompt>'.
    assert 'appendSuppressedDialog("prompt(\\"\\"): \\(prompt)", for: webView)' in source


def test_confirm_handler_honors_policy() -> None:
    source = read(UI_DELEGATE)
    assert 'DialogPolicy.confirm == "accept"' in source
    # Default dismiss path still returns false; accept path returns true.
    assert "completionHandler(false)" in source
    assert "completionHandler(true)" in source


def test_click_clears_and_drains_dialog_evidence() -> None:
    source = read(INPUT)
    click_body = source.split("func click(selector:")[1]
    # Dialog evidence cleared at click entry, next to the popup clear.
    assert "pendingSuppressedDialogs = []" in click_body.split("if native {")[0]
    # Drained at every popup-redirect drain site (6 return paths inside click).
    assert source.count("drainSuppressedDialogs(into: &") == 6, source.count("drainSuppressedDialogs(into: &")
    # Drain emits a JSON-encoded array under suppressedDialogs when non-empty.
    assert 'result["suppressedDialogs"] = json' in source
    assert "JSONEncoder().encode(dialogs)" in source


def test_observe_reports_pending_dialog_count() -> None:
    source = read(SESSION)
    assert '"suppressedDialogCount": String(pendingSuppressedDialogs.count)' in source


def test_rpc_binds_confirm_policy_nested_in_tab_target() -> None:
    source = read(RPC)
    assert 'DialogPolicy.$confirm.withValue(params["confirm"])' in source
    # Confirm binding must nest inside the existing TabTarget binding.
    tab_index = source.index("TabTarget.$tabID.withValue(requestedTabID)")
    confirm_index = source.index('DialogPolicy.$confirm.withValue(params["confirm"])')
    assert tab_index < confirm_index


def test_cli_exposes_global_confirm_option() -> None:
    options = read(CLI_OPTIONS)
    assert '"--confirm"' in options
    assert "confirm: String?" in options
    main = read(MAIN)
    assert 'params["confirm"] = confirm' in main


def test_mcp_threads_confirm_for_click_and_evaluate_only() -> None:
    source = read(MCP)
    # _run_cli accepts confirm and appends --confirm exactly like --tab.
    assert 'confirm: str = ""' in source
    assert '["--confirm", confirm] if confirm else []' in source
    # click and evaluate tools forward confirm.
    assert "def click(selector: str, native: bool = False, fallback: bool = True, tab: str = \"\", confirm: str = \"\")" in source
    assert "def evaluate(script: str, tab: str = \"\", confirm: str = \"\")" in source
    assert '_run_cli("click", *args, tab=tab, confirm=confirm)' in source
    assert '_run_cli("evaluate", script, tab=tab, confirm=confirm)' in source


def main() -> int:
    test_per_tab_dialog_buffer_mirrors_popup_shape()
    test_dialog_policy_task_local_exists()
    test_ui_delegate_records_dialog_evidence()
    test_confirm_handler_honors_policy()
    test_click_clears_and_drains_dialog_evidence()
    test_observe_reports_pending_dialog_count()
    test_rpc_binds_confirm_policy_nested_in_tab_target()
    test_cli_exposes_global_confirm_option()
    test_mcp_threads_confirm_for_click_and_evaluate_only()
    print("dialog evidence contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
