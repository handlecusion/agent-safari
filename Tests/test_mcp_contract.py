#!/usr/bin/env python3
"""Regression tests for the public MCP wrapper contract."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "mcp" / "agent_safari_mcp.py"

EXPECTED_TOOLS = {
    "status",
    "observe",
    "navigate",
    "text",
    "html",
    "title",
    "url",
    "content",
    "snapshot",
    "evaluate",
    "screenshot",
    "screenshot_full",
    "screenshot_element",
    "click",
    "fill",
    "key",
    "type_text",
    "wait",
    "wait_for_selector",
    "wait_for_text",
    "wait_for_url",
    "wait_for_title",
    "wait_for_visible",
    "wait_for_idle",
    "network_start",
    "network_list",
    "network_stop",
    "network_export",
    "back",
    "forward",
    "reload",
    "viewport",
    "session",
    "tabs",
    "tab_new",
    "tab_switch",
    "tab_close",
}


def load_contract() -> list[dict[str, object]]:
    completed = subprocess.run(
        [sys.executable, str(WRAPPER), "--tools-json"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(completed.stdout)


def tool_names(tools: list[dict[str, object]]) -> set[str]:
    return {str(tool["name"]) for tool in tools}


def test_tools_json_lists_stable_tool_contract() -> None:
    tools = load_contract()
    names = tool_names(tools)
    missing = EXPECTED_TOOLS - names
    extra = names - EXPECTED_TOOLS
    assert not missing, f"missing tools: {sorted(missing)}"
    assert not extra, f"unexpected tools: {sorted(extra)}"

    for tool in tools:
        assert isinstance(tool.get("description"), str) and tool["description"]
        assert isinstance(tool.get("cli"), list) and tool["cli"]
        assert isinstance(tool.get("result"), list)
        assert tool.get("contractVersion") == 1
        assert isinstance(tool.get("input"), list)


def test_network_tools_advertise_structured_result_shape() -> None:
    tools = {tool["name"]: tool for tool in load_contract()}
    for name in ("network_start", "network_list", "network_stop"):
        assert tools[name]["result"] == ["capturing", "count", "events"]


def test_agent_loop_tools_advertise_exact_cli_shapes_and_inputs() -> None:
    tools = {tool["name"]: tool for tool in load_contract()}
    expected = {
        "status": {"cli": ["status"], "input": [], "result": ["url", "title", "loading", "sessionId", "tabId"]},
        "screenshot": {"cli": ["screenshot", "--out", "<path>"], "input": ["path"]},
        "screenshot_full": {"cli": ["screenshot", "--full", "--out", "<path>"], "input": ["path"]},
        "screenshot_element": {"cli": ["screenshot-element", "<selector-or-ref>", "--out", "<path>"], "input": ["selector", "path"]},
        "click": {
            "cli": ["click", "<selector-or-ref>", "[--native]", "[--no-fallback]"],
            "input": ["selector", "native", "fallback"],
            "result": ["selector", "result", "strategy", "method", "nativeVerified", "fallbackUsed", "nativeError"],
        },
        "wait_for_selector": {"cli": ["wait-for-selector", "<selector>", "--timeout", "<ms>"], "input": ["selector", "timeout_ms"], "result": ["selector", "found", "timeoutMs"]},
        "wait_for_text": {"cli": ["wait-for-text", "<text>", "--timeout", "<ms>"], "input": ["text", "timeout_ms"], "result": ["text", "found", "timeoutMs"]},
        "wait_for_url": {"cli": ["wait-for-url", "<url-substring>", "--timeout", "<ms>"], "input": ["url", "timeout_ms"], "result": ["url", "matched", "currentURL", "timeoutMs"]},
        "wait_for_title": {"cli": ["wait-for-title", "<title-substring>", "--timeout", "<ms>"], "input": ["title", "timeout_ms"], "result": ["title", "matched", "currentTitle", "timeoutMs"]},
        "wait_for_visible": {"cli": ["wait-for-visible", "<selector-or-ref>", "--timeout", "<ms>"], "input": ["selector", "timeout_ms"], "result": ["selector", "visible", "timeoutMs"]},
        "wait_for_idle": {"cli": ["wait-for-idle", "--timeout", "<ms>"], "input": ["timeout_ms"], "result": ["idle", "timeoutMs", "quietWindowMs"]},
        "network_export": {"cli": ["network", "export", "<path>", "[--body-preview-bytes <n>]", "[--max-entries <n>]"], "input": ["path", "body_preview_bytes", "max_entries"], "result": ["path", "count", "redacted", "schema", "schemaVersion", "captureType", "limitations", "bodyPreviewBytes", "maxEntries", "entryCount", "eventCount", "resourceTimingCount", "redactionPolicy"]},
        "session": {"cli": ["session"], "input": [], "result": ["sessionId", "activeTabId", "profile", "persistent", "dataStore", "tabCount"]},
        "tabs": {"cli": ["tabs"], "input": [], "result": ["tabs", "activeTabId"]},
        "tab_new": {"cli": ["tab-new", "[url]"], "input": ["url"], "result": ["id", "tabId", "created", "url", "title"]},
        "tab_switch": {"cli": ["tab-switch", "<id>"], "input": ["tab_id"], "result": ["id", "tabId", "active", "url", "title"]},
        "tab_close": {"cli": ["tab-close", "<id>"], "input": ["tab_id"], "result": ["id", "tabId", "closed", "activeTabId", "reason"]},
    }
    for name, contract in expected.items():
        assert tools[name]["cli"] == contract["cli"], name
        assert tools[name]["input"] == contract["input"], name
        if "result" in contract:
            assert tools[name]["result"] == contract["result"], name


def main() -> int:
    for test in (
        test_tools_json_lists_stable_tool_contract,
        test_network_tools_advertise_structured_result_shape,
        test_agent_loop_tools_advertise_exact_cli_shapes_and_inputs,
    ):
        test()
    print("mcp contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
