#!/usr/bin/env python3
"""Regression tests for the public MCP wrapper contract."""

from __future__ import annotations

import importlib.util
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


def load_wrapper_module():
    spec = importlib.util.spec_from_file_location("agent_safari_mcp", WRAPPER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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
        assert tools[name]["result"] == ["capturing", "count", "events", "tabId"]


def test_agent_loop_tools_advertise_exact_cli_shapes_and_inputs() -> None:
    tools = {tool["name"]: tool for tool in load_contract()}
    expected = {
        "status": {"cli": ["status", "[--tab <id>]"], "input": ["tab"], "result": ["url", "title", "loading", "sessionId", "tabId"]},
        "screenshot": {"cli": ["screenshot", "--out", "<path>", "[--tab <id>]"], "input": ["path", "tab"]},
        "screenshot_full": {"cli": ["screenshot", "--full", "--out", "<path>", "[--tab <id>]"], "input": ["path", "tab"]},
        "screenshot_element": {"cli": ["screenshot-element", "<selector-or-ref>", "--out", "<path>", "[--tab <id>]"], "input": ["selector", "path", "tab"]},
        "click": {
            "cli": ["click", "<selector-or-ref>", "[--native]", "[--no-fallback]", "[--confirm <accept|dismiss>]", "[--tab <id>]"],
            "input": ["selector", "native", "fallback", "confirm", "tab"],
            "result": ["selector", "result", "strategy", "method", "nativeVerified", "fallbackUsed", "nativeError", "nativeErrorCode", "popupRedirectedURL", "suppressedDialogs", "coordinateStrategy", "viewportX", "viewportY", "boundsX", "boundsY", "boundsWidth", "boundsHeight", "viewportWidth", "viewportHeight", "scrollDeltaX", "scrollDeltaY", "scrolledIntoView", "tabId"],
        },
        "evaluate": {
            "cli": ["evaluate", "<script>", "[--confirm <accept|dismiss>]", "[--tab <id>]"],
            "input": ["script", "confirm", "tab"],
            "result": ["value", "tabId"],
        },
        "fill": {"cli": ["fill", "<selector-or-ref>", "<value>", "[--tab <id>]"], "input": ["selector", "value", "tab"], "result": ["selector", "value", "tabId"]},
        "wait_for_selector": {"cli": ["wait-for-selector", "<selector>", "--timeout", "<ms>", "[--tab <id>]"], "input": ["selector", "timeout_ms", "tab"], "result": ["selector", "found", "timeoutMs", "tabId"]},
        "wait_for_text": {"cli": ["wait-for-text", "<text>", "--timeout", "<ms>", "[--tab <id>]"], "input": ["text", "timeout_ms", "tab"], "result": ["text", "found", "timeoutMs", "tabId"]},
        "wait_for_url": {"cli": ["wait-for-url", "<url-substring>", "--timeout", "<ms>", "[--tab <id>]"], "input": ["url", "timeout_ms", "tab"], "result": ["url", "matched", "currentURL", "timeoutMs", "tabId"]},
        "wait_for_title": {"cli": ["wait-for-title", "<title-substring>", "--timeout", "<ms>", "[--tab <id>]"], "input": ["title", "timeout_ms", "tab"], "result": ["title", "matched", "currentTitle", "timeoutMs", "tabId"]},
        "wait_for_visible": {"cli": ["wait-for-visible", "<selector-or-ref>", "--timeout", "<ms>", "[--tab <id>]"], "input": ["selector", "timeout_ms", "tab"], "result": ["selector", "visible", "timeoutMs", "tabId"]},
        "wait_for_idle": {"cli": ["wait-for-idle", "--timeout", "<ms>", "[--tab <id>]"], "input": ["timeout_ms", "tab"], "result": ["idle", "timeoutMs", "quietWindowMs", "tabId"]},
        "network_export": {"cli": ["network", "export", "<path>", "[--body-preview-bytes <n>]", "[--max-entries <n>]", "[--tab <id>]"], "input": ["path", "body_preview_bytes", "max_entries", "tab"], "result": ["path", "count", "redacted", "schema", "schemaVersion", "captureType", "limitations", "bodyPreviewBytes", "maxEntries", "entryCount", "eventCount", "resourceTimingCount", "redactionPolicy", "tabId"]},
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


def test_failed_cli_payload_preserves_error_code_in_mcp_exception() -> None:
    module = load_wrapper_module()
    original_bin = module.os.environ.get("AGENT_SAFARI_BIN")
    original_run = module.subprocess.run
    payload = {
        "ok": False,
        "error": {
            "code": "actionability_hidden",
            "message": "Element is hidden: #hidden",
        },
    }

    def fake_run(*_args, **_kwargs):
        return subprocess.CompletedProcess(
            args=["agent-safari"],
            returncode=0,
            stdout=json.dumps(payload) + "\n",
            stderr="",
        )

    try:
        module.os.environ["AGENT_SAFARI_BIN"] = "/bin/echo"
        module.subprocess.run = fake_run
        try:
            module._run_cli("click", "#hidden")
        except RuntimeError as exc:
            assert getattr(exc, "code", None) == "actionability_hidden"
            assert "[actionability_hidden]" in str(exc)
            assert "Element is hidden: #hidden" in str(exc)
        else:
            raise AssertionError("expected MCP wrapper to raise on failed CLI payload")
    finally:
        module.subprocess.run = original_run
        if original_bin is None:
            module.os.environ.pop("AGENT_SAFARI_BIN", None)
        else:
            module.os.environ["AGENT_SAFARI_BIN"] = original_bin


def main() -> int:
    for test in (
        test_tools_json_lists_stable_tool_contract,
        test_network_tools_advertise_structured_result_shape,
        test_agent_loop_tools_advertise_exact_cli_shapes_and_inputs,
        test_failed_cli_payload_preserves_error_code_in_mcp_exception,
    ):
        test()
    print("mcp contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
