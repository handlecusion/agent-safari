#!/usr/bin/env python3
"""Contract checks for console/page-error capture (mirrors test_network_capture_contract.py style)."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONSOLE = ROOT / "Sources" / "AgentSafari" / "BrowserControllerConsole.swift"
MCP = ROOT / "mcp" / "agent_safari_mcp.py"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_console_script_captures_errors_and_warnings_not_log() -> None:
    source = read(CONSOLE)
    # Must wrap error and warn
    assert "console.error" in source
    assert "console.warn" in source
    # Must NOT wrap console.log (noise)
    assert "console.log" not in source


def test_console_script_captures_window_error_and_unhandledrejection() -> None:
    source = read(CONSOLE)
    assert "addEventListener('error'" in source
    assert "addEventListener('unhandledrejection'" in source


def test_console_ring_buffer_capped_at_200() -> None:
    source = read(CONSOLE)
    assert "MAX_ENTRIES = 200" in source
    assert "__agentSafariConsoleEvents.splice" in source


def test_console_entry_shape_fields() -> None:
    source = read(CONSOLE)
    # Fields appear as unquoted JS object keys: `type:`, `level:`, etc.
    required_fields = ["type", "level", "message", "source", "line", "ts"]
    for field in required_fields:
        assert f"{field}:" in source, f"missing entry field {field!r}"


def test_console_gate_flag() -> None:
    source = read(CONSOLE)
    assert "__agentSafariConsoleCaptureEnabled" in source
    assert "__agentSafariConsoleCaptureInstalled" in source


def test_console_start_installs_once_clears_enables() -> None:
    source = read(CONSOLE)
    # consoleStart must: install user script once, enable, clear
    assert "consoleUserScriptInstalled" in source
    assert "__agentSafariConsoleCaptureEnabled = true" in source
    assert "__agentSafariConsoleEvents.length = 0" in source


def test_console_stop_disables_keeps_events_readable() -> None:
    source = read(CONSOLE)
    # consoleStop disables capture but list result is returned first (events readable)
    assert "consoleList()" in source
    assert "__agentSafariConsoleCaptureEnabled = false" in source


def test_mcp_console_contract_result_fields() -> None:
    namespace: dict[str, object] = {}
    exec(MCP.read_text(encoding="utf-8"), namespace)
    tool_contracts = namespace["TOOL_CONTRACTS"]
    assert isinstance(tool_contracts, list)
    contracts = {tool["name"]: tool for tool in tool_contracts}

    for name in ("console_start", "console_list", "console_stop"):
        assert name in contracts, f"missing MCP tool {name}"
        result = contracts[name]["result"]
        assert result == ["capturing", "count", "events", "tabId"], f"unexpected result for {name}: {result}"
        assert contracts[name]["input"] == ["tab"], f"unexpected input for {name}"

    # CLI shape
    assert contracts["console_start"]["cli"] == ["console", "start", "[--tab <id>]"]
    assert contracts["console_list"]["cli"] == ["console", "list", "[--tab <id>]"]
    assert contracts["console_stop"]["cli"] == ["console", "stop", "[--tab <id>]"]


def test_console_capture_honesty_language() -> None:
    source = read(CONSOLE)
    # Capture type is JS instrumentation - ensure no overclaiming
    assert "installAgentSafariConsoleCapture" in source


def main() -> int:
    for test in (
        test_console_script_captures_errors_and_warnings_not_log,
        test_console_script_captures_window_error_and_unhandledrejection,
        test_console_ring_buffer_capped_at_200,
        test_console_entry_shape_fields,
        test_console_gate_flag,
        test_console_start_installs_once_clears_enables,
        test_console_stop_disables_keeps_events_readable,
        test_mcp_console_contract_result_fields,
        test_console_capture_honesty_language,
    ):
        test()
    print("console capture contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
