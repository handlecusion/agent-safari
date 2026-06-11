#!/usr/bin/env python3
"""Regression contracts for the cookies export/import commands."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ERROR = ROOT / "Sources" / "AgentSafari" / "AgentSafariError.swift"
COOKIES = ROOT / "Sources" / "AgentSafari" / "BrowserControllerCookies.swift"
COMMAND = ROOT / "Sources" / "AgentSafariCore" / "CommandRequest.swift"
METADATA = ROOT / "Sources" / "AgentSafariCore" / "AgentSafariMetadata.swift"
RPC = ROOT / "Sources" / "AgentSafari" / "RPCHandler.swift"
CLI_HELPERS = ROOT / "Sources" / "AgentSafari" / "CLIHelpers.swift"
WRAPPER = ROOT / "mcp" / "agent_safari_mcp.py"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_error_case_and_code_exist() -> None:
    source = read(ERROR)
    assert "case cookieFileInvalid(String)" in source
    assert '"cookie_file_invalid"' in source
    assert '"Cookie file invalid:' in source


def test_cookies_swift_file_structure() -> None:
    source = read(COOKIES)
    # Export function
    assert "func cookiesExport(path: String) async throws -> [String: String]" in source
    # Uses httpCookieStore getAllCookies with continuation
    assert "httpCookieStore" in source
    assert "getAllCookies" in source
    assert "withCheckedThrowingContinuation" in source
    # Writes schemaVersion 1
    assert '"schemaVersion"' in source
    assert '"cookies"' in source
    # Sets 0600 permissions
    assert "0o600" in source
    # Import function
    assert "func cookiesImport(path: String) async throws -> [String: String]" in source
    # Validates required fields
    assert "missing required fields (name, value, domain, path)" in source
    # Uses setCookie with continuation
    assert "setCookie" in source
    # Returns path and count
    assert '"path"' in source
    assert '"count"' in source
    # Documents that --tab has no effect
    assert "--tab" in source


def test_command_request_parses_cookies_commands() -> None:
    source = read(COMMAND)
    # Hyphenated aliases
    assert 'case "cookies-export":' in source
    assert 'case "cookies-import":' in source
    # Subcommand dispatch
    assert 'case "cookies":' in source
    assert "parseCookiesCommand" in source
    # Subcommand sub-cases
    assert 'case "export":' in source
    assert 'case "import":' in source
    # Maps to RPC methods
    assert 'method: "cookiesExport"' in source
    assert 'method: "cookiesImport"' in source


def test_metadata_advertises_cookies_commands() -> None:
    source = read(METADATA)
    assert '"cookies"' in source
    assert '"cookies-export"' in source
    assert '"cookies-import"' in source


def test_rpc_dispatches_cookies_commands() -> None:
    source = read(RPC)
    assert 'case "cookiesExport":' in source
    assert 'case "cookiesImport":' in source
    assert "browser.cookiesExport(path: path)" in source
    assert "browser.cookiesImport(path: path)" in source


def test_cli_usage_lists_cookies() -> None:
    source = read(CLI_HELPERS)
    assert "cookies export <path>" in source
    assert "cookies import <path>" in source


def test_mcp_wrapper_exposes_cookies_tools() -> None:
    source = read(WRAPPER)
    assert "def cookies_export(path: str)" in source
    assert "def cookies_import(path: str)" in source
    assert '_run_cli("cookies", "export", path)' in source
    assert '_run_cli("cookies", "import", path)' in source


def test_mcp_tools_json_pins_cookies_contract() -> None:
    completed = subprocess.run(
        [sys.executable, str(WRAPPER), "--tools-json"],
        check=True,
        capture_output=True,
        text=True,
    )
    tools = {tool["name"]: tool for tool in json.loads(completed.stdout)}
    assert "cookies_export" in tools
    assert "cookies_import" in tools

    export = tools["cookies_export"]
    assert export["cli"] == ["cookies", "export", "<path>"]
    assert export["input"] == ["path"]
    assert export["result"] == ["path", "count", "tabId"]

    imp = tools["cookies_import"]
    assert imp["cli"] == ["cookies", "import", "<path>"]
    assert imp["input"] == ["path"]
    assert imp["result"] == ["path", "count", "tabId"]


def main() -> int:
    test_error_case_and_code_exist()
    test_cookies_swift_file_structure()
    test_command_request_parses_cookies_commands()
    test_metadata_advertises_cookies_commands()
    test_rpc_dispatches_cookies_commands()
    test_cli_usage_lists_cookies()
    test_mcp_wrapper_exposes_cookies_tools()
    test_mcp_tools_json_pins_cookies_contract()
    print("cookie transfer contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
