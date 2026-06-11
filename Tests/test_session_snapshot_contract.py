#!/usr/bin/env python3
"""Regression contracts for the `session-snapshot` command."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ERROR = ROOT / "Sources" / "AgentSafari" / "AgentSafariError.swift"
CONTROLLER = ROOT / "Sources" / "AgentSafari" / "BrowserController.swift"
SESSION = ROOT / "Sources" / "AgentSafari" / "BrowserControllerSession.swift"
COMMAND = ROOT / "Sources" / "AgentSafariCore" / "CommandRequest.swift"
METADATA = ROOT / "Sources" / "AgentSafariCore" / "AgentSafariMetadata.swift"
RPC = ROOT / "Sources" / "AgentSafari" / "RPCHandler.swift"
CLI_HELPERS = ROOT / "Sources" / "AgentSafari" / "CLIHelpers.swift"
WRAPPER = ROOT / "mcp" / "agent_safari_mcp.py"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_artifact_write_failed_error_exists() -> None:
    source = read(ERROR)
    assert "case artifactWriteFailed(String)" in source
    assert '"artifact_write_failed"' in source
    assert "Failed to write session snapshot artifact:" in source


def test_session_snapshot_method_exists() -> None:
    source = read(SESSION)
    assert "func sessionSnapshot(path: String) async throws" in source
    # Schema fields
    assert '"schemaVersion"' in source
    assert '"sessionId"' in source
    assert '"profile"' in source
    assert '"persistent"' in source
    assert '"dataStore"' in source
    assert '"activeTabId"' in source
    assert '"viewport"' in source
    assert '"tabs"' in source
    # Per-tab fields
    assert '"networkCapturing"' in source
    assert '"consoleCapturing"' in source
    assert '"pendingSuppressedDialogCount"' in source
    # Parent dir creation and atomic write
    assert "createDirectory" in source
    assert ".atomic" in source
    # Error on write failure
    assert "AgentSafariError.artifactWriteFailed" in source


def test_per_tab_state_dicts_accessible() -> None:
    source = read(CONTROLLER)
    # Must be internal (not private) so the extension in BrowserControllerSession.swift can read them
    assert "var networkCaptureActiveByTab" in source
    assert "var consoleCaptureActiveByTab" in source
    assert "var pendingSuppressedDialogsByTab" in source
    # Must not be private
    assert "private var networkCaptureActiveByTab" not in source
    assert "private var consoleCaptureActiveByTab" not in source
    assert "private var pendingSuppressedDialogsByTab" not in source


def test_command_request_parses_session_snapshot() -> None:
    source = read(COMMAND)
    assert 'case "session-snapshot":' in source
    snap_case = source.split('case "session-snapshot":')[1].split("case ")[0]
    assert 'method: "sessionSnapshot"' in snap_case
    assert '"path"' in snap_case


def test_metadata_advertises_session_snapshot() -> None:
    assert '"session-snapshot"' in read(METADATA)


def test_rpc_dispatches_session_snapshot() -> None:
    source = read(RPC)
    assert 'case "sessionSnapshot":' in source
    snap_case = source.split('case "sessionSnapshot":')[1].split("case ")[0]
    assert "browser.sessionSnapshot(path: path)" in snap_case


def test_cli_usage_lists_session_snapshot() -> None:
    assert "agent-safari session-snapshot <path>" in read(CLI_HELPERS)


def test_mcp_wrapper_exposes_session_snapshot_tool() -> None:
    source = read(WRAPPER)
    assert "def session_snapshot(path: str)" in source
    assert '_run_cli("session-snapshot", path)' in source


def test_mcp_tools_json_pins_session_snapshot_contract() -> None:
    completed = subprocess.run(
        [sys.executable, str(WRAPPER), "--tools-json"],
        check=True,
        capture_output=True,
        text=True,
    )
    tools = {tool["name"]: tool for tool in json.loads(completed.stdout)}
    assert "session_snapshot" in tools
    snap = tools["session_snapshot"]
    assert snap["cli"] == ["session-snapshot", "<path>"]
    assert snap["input"] == ["path"]
    assert "path" in snap["result"]
    assert "tabCount" in snap["result"]


def main() -> int:
    test_artifact_write_failed_error_exists()
    test_session_snapshot_method_exists()
    test_per_tab_state_dicts_accessible()
    test_command_request_parses_session_snapshot()
    test_metadata_advertises_session_snapshot()
    test_rpc_dispatches_session_snapshot()
    test_cli_usage_lists_session_snapshot()
    test_mcp_wrapper_exposes_session_snapshot_tool()
    test_mcp_tools_json_pins_session_snapshot_contract()
    print("session snapshot contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
