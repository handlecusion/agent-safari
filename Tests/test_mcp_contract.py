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
    "click",
    "fill",
    "key",
    "type_text",
    "wait",
    "wait_for_selector",
    "wait_for_text",
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


def test_network_tools_advertise_structured_result_shape() -> None:
    tools = {tool["name"]: tool for tool in load_contract()}
    for name in ("network_start", "network_list", "network_stop"):
        assert tools[name]["result"] == ["capturing", "count", "events"]


def main() -> int:
    for test in (test_tools_json_lists_stable_tool_contract, test_network_tools_advertise_structured_result_shape):
        test()
    print("mcp contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
