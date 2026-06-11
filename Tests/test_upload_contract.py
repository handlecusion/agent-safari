#!/usr/bin/env python3
"""Regression contracts for the `upload` command and <input type=file> driving."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ERROR = ROOT / "Sources" / "AgentSafari" / "AgentSafariError.swift"
CONTROLLER = ROOT / "Sources" / "AgentSafari" / "BrowserController.swift"
UI_DELEGATE = ROOT / "Sources" / "AgentSafari" / "BrowserControllerUIDelegate.swift"
INPUT = ROOT / "Sources" / "AgentSafari" / "BrowserControllerInput.swift"
SESSION = ROOT / "Sources" / "AgentSafari" / "BrowserControllerSession.swift"
COMMAND = ROOT / "Sources" / "AgentSafariCore" / "CommandRequest.swift"
METADATA = ROOT / "Sources" / "AgentSafariCore" / "AgentSafariMetadata.swift"
RPC = ROOT / "Sources" / "AgentSafari" / "RPCHandler.swift"
CLI_HELPERS = ROOT / "Sources" / "AgentSafari" / "CLIHelpers.swift"
WRAPPER = ROOT / "mcp" / "agent_safari_mcp.py"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_upload_error_cases_and_codes_exist() -> None:
    source = read(ERROR)
    assert "case uploadFileNotFound(String)" in source
    assert "case uploadPanelNotTriggered(String)" in source
    assert "case uploadMultipleNotAllowed(String)" in source
    assert '"upload_file_not_found"' in source
    assert '"upload_panel_not_triggered"' in source
    assert '"upload_multiple_not_allowed"' in source


def test_per_tab_pending_upload_state_exists_and_is_cleared() -> None:
    source = read(CONTROLLER)
    assert "pendingUploadFileURLsByTab: [ObjectIdentifier: [URL]]" in source
    assert "func armPendingUploadFileURLs(" in source
    assert "func consumePendingUploadFileURLs(" in source
    # clearPerTabState must drop pending uploads alongside popup/network state
    clear_body = source.split("func clearPerTabState(")[1].split("\n    }")[0]
    assert "pendingUploadFileURLsByTab.removeValue" in clear_body


def test_tab_close_clears_per_tab_state() -> None:
    source = read(SESSION)
    assert "clearPerTabState(for: closingWebView)" in source


def test_run_open_panel_is_implemented() -> None:
    source = read(UI_DELEGATE)
    assert "runOpenPanelWith parameters: WKOpenPanelParameters" in source
    assert "completionHandler: @escaping ([URL]?) -> Void" in source
    # Armed files are consumed and delivered; otherwise the panel is dismissed + logged
    assert "consumePendingUploadFileURLs(for: webView)" in source
    assert "completionHandler(urls)" in source
    assert "completionHandler(nil)" in source
    assert "open panel dismissed (no pending upload files)" in source


def test_upload_method_arms_before_click_and_verifies_count() -> None:
    source = read(INPUT)
    assert "func upload(selector: String, paths: [String]) async throws" in source
    upload_body = source.split("func upload(selector: String, paths: [String])")[1]
    # Validate every path exists before doing anything
    assert "FileManager.default.fileExists(atPath: path)" in upload_body
    assert "AgentSafariError.uploadFileNotFound(path)" in upload_body
    # Arming must precede the click so the panel callback has files to consume
    arm_index = upload_body.index("armPendingUploadFileURLs(fileURLs, for: targetWebView)")
    click_index = upload_body.index("clickUploadElement(selector: selector)")
    assert arm_index < click_index, "must arm pending upload URLs before clicking"
    # Verify file count and report files/fileCount/changeEventSynthesized
    assert "uploadVerification(selector: selector)" in upload_body
    assert '"fileCount"' in upload_body
    assert '"files"' in upload_body
    assert '"changeEventSynthesized"' in upload_body
    # If the panel never fired, disarm and raise the explicit error
    assert "pendingUploadFileURLs(for: targetWebView) != nil" in upload_body
    assert "AgentSafariError.uploadPanelNotTriggered(selector)" in upload_body
    # Multiple-files rule enforced
    assert "uploadMultipleNotAllowed" in source


def test_command_request_encodes_paths_as_json_array() -> None:
    source = read(COMMAND)
    assert 'case "upload":' in source
    upload_case = source.split('case "upload":')[1].split("case ")[0]
    assert "JSONEncoder().encode(paths)" in upload_case
    assert 'method: "upload"' in upload_case
    assert '"paths": pathsJSON' in upload_case


def test_metadata_advertises_upload_command() -> None:
    assert '"upload"' in read(METADATA)


def test_rpc_dispatches_upload_and_decodes_paths() -> None:
    source = read(RPC)
    assert 'case "upload":' in source
    upload_case = source.split('case "upload":')[1].split("case ")[0]
    assert "JSONDecoder().decode([String].self" in upload_case
    assert "browser.upload(selector: selector, paths: paths)" in upload_case


def test_cli_usage_lists_upload() -> None:
    assert "agent-safari upload <selector-or-ref> <path>" in read(CLI_HELPERS)


def test_mcp_wrapper_exposes_upload_tool() -> None:
    source = read(WRAPPER)
    assert "def upload(selector: str, paths: list[str], tab: str" in source
    assert '_run_cli("upload", selector, *paths, tab=tab)' in source


def test_mcp_tools_json_pins_upload_contract() -> None:
    completed = subprocess.run(
        [sys.executable, str(WRAPPER), "--tools-json"],
        check=True,
        capture_output=True,
        text=True,
    )
    tools = {tool["name"]: tool for tool in json.loads(completed.stdout)}
    assert "upload" in tools
    upload = tools["upload"]
    assert upload["cli"] == ["upload", "<selector-or-ref>", "<path>", "[<path>...]", "[--tab <id>]"]
    assert upload["input"] == ["selector", "paths", "tab"]
    assert upload["result"] == ["selector", "files", "fileCount", "changeEventSynthesized", "strategy", "tabId"]


def main() -> int:
    test_upload_error_cases_and_codes_exist()
    test_per_tab_pending_upload_state_exists_and_is_cleared()
    test_tab_close_clears_per_tab_state()
    test_run_open_panel_is_implemented()
    test_upload_method_arms_before_click_and_verifies_count()
    test_command_request_encodes_paths_as_json_array()
    test_metadata_advertises_upload_command()
    test_rpc_dispatches_upload_and_decodes_paths()
    test_cli_usage_lists_upload()
    test_mcp_wrapper_exposes_upload_tool()
    test_mcp_tools_json_pins_upload_contract()
    print("upload contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
