#!/usr/bin/env python3
"""Regression contracts for media observation, wait predicate, and playback control."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ERROR = ROOT / "Sources" / "AgentSafari" / "AgentSafariError.swift"
CONTROLLER = ROOT / "Sources" / "AgentSafari" / "BrowserController.swift"
MEDIA = ROOT / "Sources" / "AgentSafari" / "BrowserControllerMedia.swift"
COMMAND = ROOT / "Sources" / "AgentSafariCore" / "CommandRequest.swift"
METADATA = ROOT / "Sources" / "AgentSafariCore" / "AgentSafariMetadata.swift"
RPC = ROOT / "Sources" / "AgentSafari" / "RPCHandler.swift"
CLI_HELPERS = ROOT / "Sources" / "AgentSafari" / "CLIHelpers.swift"
WRAPPER = ROOT / "mcp" / "agent_safari_mcp.py"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_media_play_rejected_error_case_and_code_exist() -> None:
    source = read(ERROR)
    assert "case mediaPlayRejected(String)" in source
    assert '"media_play_rejected"' in source
    # Fractional, non-negative seek seconds parser reuses the invalid_param style.
    assert "func parseNonNegativeDoubleParam(" in source


def test_make_webview_allows_programmatic_playback() -> None:
    source = read(CONTROLLER)
    assert "configuration.mediaTypesRequiringUserActionForPlayback = []" in source


def test_media_inventory_reports_documented_fields() -> None:
    source = read(MEDIA)
    assert "func media() async throws -> [String: String]" in source
    # Read-only inventory enumerates both media element kinds.
    assert "document.querySelectorAll('video, audio')" in source
    for field in (
        "currentSrc",
        "duration",
        "paused",
        "ended",
        "muted",
        "volume",
        "currentTime",
        "readyState",
        "videoWidth",
        "videoHeight",
        "poster",
    ):
        assert field in source, field
    # NaN/Infinity duration is normalized to -1 ("unknown") so JSON round-trips.
    assert "numberOrUnknown" in source
    assert "? value : -1" in source


def test_wait_for_media_states_and_semantics() -> None:
    source = read(MEDIA)
    assert "func waitForMedia(selector: String, state: String, timeoutMs: Int)" in source
    assert '["playing", "paused", "ended", "canplay"]' in source
    # Exact predicate semantics required by the contract.
    assert "!element.paused && !element.ended && element.readyState >= 2" in source
    assert "element.readyState >= 3" in source
    # Timeout maps to the shared wait_timeout code.
    assert "AgentSafariError.waitTimedOut" in source
    # Element resolution reuses the actionability-coded resolver.
    assert "actionability_refs_unavailable" in source
    assert "actionability_stale_ref" in source
    assert "actionability_missing_selector" in source


def test_media_control_actions_and_play_rejection() -> None:
    source = read(MEDIA)
    assert "func mediaControl(selector: String, action: String, seconds: Double?)" in source
    assert '["play", "pause", "mute", "unmute", "seek"]' in source
    # seek requires seconds.
    assert 'if action == "seek", seconds == nil' in source
    assert 'AgentSafariError.missingParam("seconds")' in source
    # play() Promise is awaited in-page (bounded so a never-settling Promise on a
    # no-source element cannot hang the daemon) and rejection becomes a structured error.
    assert "callAsyncJavaScript" in source
    assert "element.play()" in source
    assert "Promise.race" in source
    assert "media_play_rejected" in source
    assert "AgentSafariError.mediaPlayRejected(message)" in source
    # Before/after evidence plus action.
    for field in (
        '"pausedBefore"',
        '"currentTimeBefore"',
        '"mutedBefore"',
        '"pausedAfter"',
        '"currentTimeAfter"',
        '"mutedAfter"',
        '"action"',
    ):
        assert field in source, field


def test_command_request_parses_media_commands() -> None:
    source = read(COMMAND)
    assert 'case "media":' in source
    assert 'case "wait-for-media":' in source
    assert 'case "media-control":' in source
    assert 'method: "media"' in source
    assert 'method: "waitForMedia"' in source
    assert 'method: "mediaControl"' in source


def test_metadata_advertises_media_commands() -> None:
    source = read(METADATA)
    assert '"media"' in source
    assert '"wait-for-media"' in source
    assert '"media-control"' in source


def test_rpc_dispatches_media_methods() -> None:
    source = read(RPC)
    assert 'case "media":' in source
    assert 'case "waitForMedia":' in source
    assert 'case "mediaControl":' in source
    # media returns parsed elements + count like snapshot. Split on the next
    # dispatch case label (not bare "case ", which also appears in `if case`).
    media_case = source.split('case "media":')[1].split('case "waitForMedia":')[0]
    assert '"elements": parsed' in media_case
    assert '"count"' in media_case
    # seek seconds parsed as a non-negative Double only when present.
    control_case = source.split('case "mediaControl":')[1].split("default:")[0]
    assert "parseNonNegativeDoubleParam" in control_case
    assert "browser.mediaControl(selector: selector, action: action, seconds: seconds)" in control_case


def test_cli_usage_lists_media_commands() -> None:
    source = read(CLI_HELPERS)
    assert "agent-safari media [--socket" in source
    assert "agent-safari wait-for-media <selector> --state <playing|paused|ended|canplay>" in source
    assert "agent-safari media-control <selector> <play|pause|mute|unmute|seek> [seconds]" in source


def test_mcp_wrapper_exposes_media_tools() -> None:
    source = read(WRAPPER)
    assert "def media(tab: str" in source
    assert "def wait_for_media(selector: str, state: str, timeout_ms: int" in source
    assert "def media_control(selector: str, action: str, seconds: float | None" in source
    assert '_run_cli("media", tab=tab)' in source
    assert '_run_cli("wait-for-media", selector, "--state", state' in source
    assert '_run_cli("media-control", *args, tab=tab)' in source


def test_mcp_tools_json_pins_media_contract() -> None:
    completed = subprocess.run(
        [sys.executable, str(WRAPPER), "--tools-json"],
        check=True,
        capture_output=True,
        text=True,
    )
    tools = {tool["name"]: tool for tool in json.loads(completed.stdout)}
    assert "media" in tools
    assert tools["media"]["cli"] == ["media", "[--tab <id>]"]
    assert tools["media"]["input"] == ["tab"]
    assert tools["media"]["result"] == ["elements", "count", "tabId"]

    assert "wait_for_media" in tools
    assert tools["wait_for_media"]["cli"] == [
        "wait-for-media", "<selector-or-ref>", "--state", "<playing|paused|ended|canplay>", "--timeout", "<ms>", "[--tab <id>]"
    ]
    assert tools["wait_for_media"]["input"] == ["selector", "state", "timeout_ms", "tab"]
    assert tools["wait_for_media"]["result"] == ["selector", "state", "matched", "timeoutMs", "tabId"]

    assert "media_control" in tools
    assert tools["media_control"]["cli"] == [
        "media-control", "<selector-or-ref>", "<play|pause|mute|unmute|seek>", "[seconds]", "[--tab <id>]"
    ]
    assert tools["media_control"]["input"] == ["selector", "action", "seconds", "tab"]
    assert tools["media_control"]["result"] == [
        "selector", "action", "pausedBefore", "currentTimeBefore", "mutedBefore", "pausedAfter", "currentTimeAfter", "mutedAfter", "tabId"
    ]


def main() -> int:
    test_media_play_rejected_error_case_and_code_exist()
    test_make_webview_allows_programmatic_playback()
    test_media_inventory_reports_documented_fields()
    test_wait_for_media_states_and_semantics()
    test_media_control_actions_and_play_rejection()
    test_command_request_parses_media_commands()
    test_metadata_advertises_media_commands()
    test_rpc_dispatches_media_methods()
    test_cli_usage_lists_media_commands()
    test_mcp_wrapper_exposes_media_tools()
    test_mcp_tools_json_pins_media_contract()
    print("media contract tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
