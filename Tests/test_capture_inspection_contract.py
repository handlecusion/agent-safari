#!/usr/bin/env python3
"""Contract checks for Phase 3 capture/inspection metadata."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCREENSHOT = ROOT / "Sources" / "AgentSafari" / "BrowserControllerScreenshot.swift"
SESSION = ROOT / "Sources" / "AgentSafari" / "BrowserControllerSession.swift"
MCP = ROOT / "mcp" / "agent_safari_mcp.py"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_screenshot_commands_report_phase3_capture_metadata_fields() -> None:
    source = read(SCREENSHOT)

    required_fields = [
        '"viewportWidth"',
        '"viewportHeight"',
        '"pageWidth"',
        '"pageHeight"',
        "scale",
        "tileCount",
        "preflightScrollCount",
        "warnings",
        '"outputPath"',
    ]
    for field in required_fields:
        assert field in source, f"missing screenshot metadata field {field}"

    assert '"tileCount": "1"' in source
    assert 'screenshotMetadata' in source


def test_observe_reports_phase3_inspection_state_fields() -> None:
    source = read(SESSION)

    required_fields = [
        '"loadState"',
        '"pendingNetworkCount"',
        '"selectedText"',
        '"viewportWidth"',
        '"viewportHeight"',
        '"pageWidth"',
        '"pageHeight"',
        '"activeElementSelector"',
    ]
    for field in required_fields:
        assert field in source, f"missing observe metadata field {field}"

    assert "__agentSafariNetworkPending" in source
    assert "getSelection" in source


def test_mcp_tool_contracts_expose_phase3_result_fields() -> None:
    namespace: dict[str, object] = {}
    exec(MCP.read_text(encoding="utf-8"), namespace)
    tool_contracts = namespace["TOOL_CONTRACTS"]
    assert isinstance(tool_contracts, list)
    contracts = {tool["name"]: tool for tool in tool_contracts}

    screenshot_result = set(contracts["screenshot"]["result"])
    full_result = set(contracts["screenshot_full"]["result"])
    element_result = set(contracts["screenshot_element"]["result"])
    observe_result = set(contracts["observe"]["result"])

    capture_required = {"outputPath", "viewportWidth", "viewportHeight", "pageWidth", "pageHeight", "scale", "tileCount", "warnings"}
    assert capture_required.issubset(screenshot_result)
    assert capture_required.union({"preflightScrollCount"}).issubset(full_result)
    assert capture_required.issubset(element_result)

    inspection_required = {"loadState", "pendingNetworkCount", "selectedText", "viewportWidth", "viewportHeight", "pageWidth", "pageHeight", "activeElementSelector"}
    assert inspection_required.issubset(observe_result)


def main() -> int:
    test_screenshot_commands_report_phase3_capture_metadata_fields()
    test_observe_reports_phase3_inspection_state_fields()
    test_mcp_tool_contracts_expose_phase3_result_fields()
    print("capture inspection contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
