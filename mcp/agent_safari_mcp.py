#!/usr/bin/env python3
"""MCP stdio wrapper for the agent-safari CLI.

The wrapper exposes MCP tools that invoke the built Swift CLI client, which in
turn talks to the agent-safari daemon over its Unix socket.

Environment:
  AGENT_SAFARI_BIN     Path to the built CLI. Defaults to ../.build/debug/agent-safari.
  AGENT_SAFARI_SOCKET  Unix socket path. Defaults to /tmp/agent-safari.sock.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path
from typing import Any

DEFAULT_SOCKET = "/tmp/agent-safari.sock"
DEFAULT_SCREENSHOT_PATH = str(Path.home() / ".agent-safari" / "artifacts" / "screenshot.png")

TOOL_CONTRACTS: list[dict[str, Any]] = [
    {"name": "status", "description": "Return daemon/page status for the controlled WebView.", "cli": ["status", "[--tab <id>]"], "input": ["tab"], "result": ["url", "title", "loading", "sessionId", "tabId"]},
    {"name": "observe", "description": "Return read-only page state for agent loops.", "cli": ["observe", "[--tab <id>]"], "input": ["tab"], "result": ["url", "title", "readyState", "loadState", "isLoading", "networkCapturing", "pendingNetworkCount", "selectedText", "viewportWidth", "viewportHeight", "pageWidth", "pageHeight", "activeElementTag", "activeElementType", "activeElementName", "activeElementId", "activeElementSelector", "tabId"]},
    {"name": "navigate", "description": "Navigate the controlled WebView to a URL.", "cli": ["open", "<url>", "[--tab <id>]"], "input": ["url", "tab"], "result": ["url", "tabId"]},
    {"name": "text", "description": "Return visible page text.", "cli": ["text", "[--tab <id>]"], "input": ["tab"], "result": ["text", "tabId"]},
    {"name": "html", "description": "Return document.documentElement.outerHTML.", "cli": ["html", "[--tab <id>]"], "input": ["tab"], "result": ["html", "tabId"]},
    {"name": "title", "description": "Return the current document title.", "cli": ["title", "[--tab <id>]"], "input": ["tab"], "result": ["title", "tabId"]},
    {"name": "url", "description": "Return the current document URL.", "cli": ["url", "[--tab <id>]"], "input": ["tab"], "result": ["url", "tabId"]},
    {"name": "content", "description": "Alias for visible page text.", "cli": ["content", "[--tab <id>]"], "input": ["tab"], "result": ["text", "tabId"]},
    {"name": "snapshot", "description": "Return visible/interactable elements with stable @e refs.", "cli": ["snapshot", "[--tab <id>]"], "input": ["tab"], "result": ["schemaVersion", "elements", "tabId"]},
    {"name": "evaluate", "description": "Evaluate JavaScript in the current page.", "cli": ["evaluate", "<script>", "[--tab <id>]"], "input": ["script", "tab"], "result": ["value", "tabId"]},
    {"name": "screenshot", "description": "Capture a viewport screenshot as a PNG file.", "cli": ["screenshot", "--out", "<path>", "[--tab <id>]"], "input": ["path", "tab"], "result": ["path", "outputPath", "width", "height", "fullPage", "viewportWidth", "viewportHeight", "pageWidth", "pageHeight", "scale", "tileCount", "warnings", "strategy", "tabId"]},
    {"name": "screenshot_full", "description": "Capture a full-page screenshot as a PNG file.", "cli": ["screenshot", "--full", "--out", "<path>", "[--tab <id>]"], "input": ["path", "tab"], "result": ["path", "outputPath", "width", "height", "fullPage", "viewportWidth", "viewportHeight", "pageWidth", "pageHeight", "scale", "tileCount", "preflightScrollCount", "warnings", "strategy", "tabId"]},
    {"name": "screenshot_element", "description": "Capture a screenshot clipped to a CSS selector or snapshot ref.", "cli": ["screenshot-element", "<selector-or-ref>", "--out", "<path>", "[--tab <id>]"], "input": ["selector", "path", "tab"], "result": ["path", "outputPath", "width", "height", "fullPage", "viewportWidth", "viewportHeight", "pageWidth", "pageHeight", "scale", "tileCount", "warnings", "element", "strategy", "tabId"]},
    {"name": "click", "description": "Click a CSS selector or snapshot ref.", "cli": ["click", "<selector-or-ref>", "[--native]", "[--no-fallback]", "[--tab <id>]"], "input": ["selector", "native", "fallback", "tab"], "result": ["selector", "result", "strategy", "method", "nativeVerified", "fallbackUsed", "nativeError", "nativeErrorCode", "popupRedirectedURL", "coordinateStrategy", "viewportX", "viewportY", "boundsX", "boundsY", "boundsWidth", "boundsHeight", "viewportWidth", "viewportHeight", "scrollDeltaX", "scrollDeltaY", "scrolledIntoView", "tabId"]},
    {"name": "fill", "description": "Fill an input-like element matching a CSS selector or snapshot ref.", "cli": ["fill", "<selector-or-ref>", "<value>", "[--tab <id>]"], "input": ["selector", "value", "tab"], "result": ["selector", "value", "tabId"]},
    {"name": "key", "description": "Dispatch synthetic DOM keyboard events.", "cli": ["key", "<key>", "[--tab <id>]"], "input": ["key", "tab"], "result": ["key", "tabId"]},
    {"name": "type_text", "description": "Insert text into the active input, textarea, or contenteditable element.", "cli": ["type", "<text>", "[--tab <id>]"], "input": ["text", "tab"], "result": ["text", "tabId"]},
    {"name": "wait", "description": "Sleep for the requested number of milliseconds in the daemon command queue.", "cli": ["wait", "<ms>", "[--tab <id>]"], "input": ["ms", "tab"], "result": ["waitedMs", "tabId"]},
    {"name": "wait_for_selector", "description": "Wait until a CSS selector exists in the current document.", "cli": ["wait-for-selector", "<selector>", "--timeout", "<ms>", "[--tab <id>]"], "input": ["selector", "timeout_ms", "tab"], "result": ["selector", "found", "timeoutMs", "tabId"]},
    {"name": "wait_for_text", "description": "Wait until document.body text contains the supplied text.", "cli": ["wait-for-text", "<text>", "--timeout", "<ms>", "[--tab <id>]"], "input": ["text", "timeout_ms", "tab"], "result": ["text", "found", "timeoutMs", "tabId"]},
    {"name": "wait_for_url", "description": "Wait until the current page URL contains the supplied substring.", "cli": ["wait-for-url", "<url-substring>", "--timeout", "<ms>", "[--tab <id>]"], "input": ["url", "timeout_ms", "tab"], "result": ["url", "matched", "currentURL", "timeoutMs", "tabId"]},
    {"name": "wait_for_title", "description": "Wait until the current document title contains the supplied substring.", "cli": ["wait-for-title", "<title-substring>", "--timeout", "<ms>", "[--tab <id>]"], "input": ["title", "timeout_ms", "tab"], "result": ["title", "matched", "currentTitle", "timeoutMs", "tabId"]},
    {"name": "wait_for_visible", "description": "Wait until a CSS selector exists and has a visible viewport-intersecting box.", "cli": ["wait-for-visible", "<selector-or-ref>", "--timeout", "<ms>", "[--tab <id>]"], "input": ["selector", "timeout_ms", "tab"], "result": ["selector", "visible", "timeoutMs", "tabId"]},
    {"name": "wait_for_idle", "description": "Wait until the page is loaded and observed fetch/XHR activity is idle.", "cli": ["wait-for-idle", "--timeout", "<ms>", "[--tab <id>]"], "input": ["timeout_ms", "tab"], "result": ["idle", "timeoutMs", "quietWindowMs", "tabId"]},
    {"name": "network_start", "description": "Start JavaScript fetch/XHR network capture instrumentation.", "cli": ["network", "start", "[--tab <id>]"], "input": ["tab"], "result": ["capturing", "count", "events", "tabId"]},
    {"name": "network_list", "description": "Return captured fetch/XHR network entries.", "cli": ["network", "list", "[--tab <id>]"], "input": ["tab"], "result": ["capturing", "count", "events", "tabId"]},
    {"name": "network_stop", "description": "Stop JavaScript fetch/XHR network capture instrumentation.", "cli": ["network", "stop", "[--tab <id>]"], "input": ["tab"], "result": ["capturing", "count", "events", "tabId"]},
    {"name": "network_export", "description": "Export captured fetch/XHR entries to a redacted JSON file.", "cli": ["network", "export", "<path>", "[--body-preview-bytes <n>]", "[--max-entries <n>]", "[--tab <id>]"], "input": ["path", "body_preview_bytes", "max_entries", "tab"], "result": ["path", "count", "redacted", "schema", "schemaVersion", "captureType", "limitations", "bodyPreviewBytes", "maxEntries", "entryCount", "eventCount", "resourceTimingCount", "redactionPolicy", "tabId"]},
    {"name": "back", "description": "Navigate back in WebKit history if possible.", "cli": ["back", "[--tab <id>]"], "input": ["tab"], "result": ["url", "tabId"]},
    {"name": "forward", "description": "Navigate forward in WebKit history if possible.", "cli": ["forward", "[--tab <id>]"], "input": ["tab"], "result": ["url", "tabId"]},
    {"name": "reload", "description": "Reload the current page.", "cli": ["reload", "[--tab <id>]"], "input": ["tab"], "result": ["url", "tabId"]},
    {"name": "viewport", "description": "Resize the controlled WebKit viewport/window.", "cli": ["viewport", "<width>", "<height>", "[--tab <id>]"], "input": ["width", "height", "tab"], "result": ["width", "height", "tabId"]},
    {"name": "session", "description": "Return current socket-scoped daemon session metadata.", "cli": ["session"], "result": ["sessionId", "activeTabId", "profile", "persistent", "dataStore", "tabCount"]},
    {"name": "tabs", "description": "List modeled tabs for the current daemon session.", "cli": ["tabs"], "result": ["tabs", "activeTabId"]},
    {"name": "tab_new", "description": "Create a new modeled WebKit tab and optionally navigate it to a URL.", "cli": ["tab-new", "[url]"], "input": ["url"], "result": ["id", "tabId", "created", "url", "title"]},
    {"name": "tab_switch", "description": "Switch to a modeled tab id.", "cli": ["tab-switch", "<id>"], "input": ["tab_id"], "result": ["id", "tabId", "active", "url", "title"]},
    {"name": "tab_close", "description": "Close a modeled tab id when supported.", "cli": ["tab-close", "<id>"], "input": ["tab_id"], "result": ["id", "tabId", "closed", "activeTabId", "reason"]},
    {"name": "downloads", "description": "List downloads observed by this daemon session (daemon-wide, capped at 50).", "cli": ["downloads"], "input": [], "result": ["downloads", "count"]},
    {"name": "wait_for_download", "description": "Wait until a download leaves the pending state; id may be a download id or --last.", "cli": ["wait-for-download", "<id-or---last>", "--timeout", "<ms>"], "input": ["download_id", "timeout_ms"], "result": ["id", "url", "filename", "path", "state", "error", "downloadTabId", "timeoutMs"]},
]

for _tool in TOOL_CONTRACTS:
    _tool.setdefault("contractVersion", 1)
    _tool.setdefault("input", [])


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def default_bin() -> str:
    return str(_repo_root() / ".build" / "debug" / "agent-safari")


def agent_safari_bin() -> str:
    return os.environ.get("AGENT_SAFARI_BIN", default_bin())


def agent_safari_socket() -> str:
    return os.environ.get("AGENT_SAFARI_SOCKET", DEFAULT_SOCKET)


class AgentSafariCLIError(RuntimeError):
    """CLI payload error that keeps the daemon's stable error code available."""

    def __init__(self, command: str, code: Any, message: str) -> None:
        self.command = command
        self.code = str(code) if code else None
        self.message = message
        code_label = f" [{self.code}]" if self.code else ""
        super().__init__(f"agent-safari {command} error{code_label}: {message}")


def _run_cli(command: str, *args: str, timeout: float = 30.0, tab: str = "") -> dict[str, Any]:
    """Run agent-safari CLI and return the decoded JSON-RPC response."""
    binary = agent_safari_bin()
    socket_path = agent_safari_socket()

    if not Path(binary).exists():
        raise RuntimeError(
            f"agent-safari binary not found at {binary!r}; build with `swift build` "
            "or set AGENT_SAFARI_BIN."
        )

    argv = [binary, command, *[str(arg) for arg in args], *(["--tab", tab] if tab else []), "--socket", socket_path]
    try:
        completed = subprocess.run(
            argv,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"agent-safari {command} timed out after {timeout}s") from exc

    stdout = completed.stdout.strip()
    stderr = completed.stderr.strip()
    if completed.returncode != 0:
        detail = stderr or stdout or f"exit code {completed.returncode}"
        raise RuntimeError(f"agent-safari {command} failed: {detail}")
    if not stdout:
        raise RuntimeError(f"agent-safari {command} returned no output")

    # The CLI prints a single JSON response line. Keep the last line to tolerate
    # incidental stdout noise from future versions.
    line = stdout.splitlines()[-1]
    try:
        payload = json.loads(line)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"agent-safari {command} returned non-JSON output: {line}") from exc

    if not payload.get("ok", False):
        error = payload.get("error") or {}
        if isinstance(error, dict):
            message = str(error.get("message") or payload)
            code = error.get("code")
        else:
            message = str(error or payload)
            code = None
        raise AgentSafariCLIError(command, code, message)
    return payload.get("result") or {}


def _help_text() -> str:
    return (
        "agent-safari MCP stdio server\n\n"
        "Run with an MCP client to expose Safari automation tools.\n"
        f"Default binary: {default_bin()}\n"
        f"Default socket: {DEFAULT_SOCKET}\n\n"
        "Environment:\n"
        "  AGENT_SAFARI_BIN     Override agent-safari CLI path\n"
        "  AGENT_SAFARI_SOCKET  Override Unix socket path\n"
    )


def create_server() -> Any:
    """Create and configure the FastMCP server.

    Importing the MCP SDK is intentionally delayed so `python -m py_compile`
    and `--help` work even before installing the optional Python dependency.
    """
    try:
        from mcp.server.fastmcp import FastMCP
    except ImportError as exc:  # pragma: no cover - depends on local environment
        raise SystemExit(
            "The Python MCP SDK is not installed. Install it with:\n"
            "  python3 -m pip install -r mcp/requirements.txt\n"
            "or:\n"
            "  python3 -m pip install 'mcp>=1.0.0'"
        ) from exc

    mcp = FastMCP("agent-safari")

    @mcp.tool()
    def status(tab: str = "") -> dict[str, Any]:
        """Return daemon/page status for the controlled Safari WebView."""
        return _run_cli("status", tab=tab)

    @mcp.tool()
    def observe(tab: str = "") -> dict[str, Any]:
        """Return read-only page state for agent loops."""
        return _run_cli("observe", tab=tab)

    @mcp.tool()
    def navigate(url: str, tab: str = "") -> dict[str, Any]:
        """Navigate the controlled Safari WebView to a URL."""
        return _run_cli("open", url, timeout=60.0, tab=tab)

    @mcp.tool()
    def text(tab: str = "") -> dict[str, Any]:
        """Return visible page text."""
        return _run_cli("text", tab=tab)

    @mcp.tool()
    def html(tab: str = "") -> dict[str, Any]:
        """Return document.documentElement.outerHTML."""
        return _run_cli("html", tab=tab)

    @mcp.tool()
    def title(tab: str = "") -> dict[str, Any]:
        """Return the current document title."""
        return _run_cli("title", tab=tab)

    @mcp.tool()
    def url(tab: str = "") -> dict[str, Any]:
        """Return the current document URL."""
        return _run_cli("url", tab=tab)

    @mcp.tool()
    def content(tab: str = "") -> dict[str, Any]:
        """Alias for visible page text."""
        return _run_cli("content", tab=tab)

    @mcp.tool()
    def snapshot(tab: str = "") -> dict[str, Any]:
        """Return a JSON string snapshot of interactive elements."""
        return _run_cli("snapshot", tab=tab)

    @mcp.tool()
    def evaluate(script: str, tab: str = "") -> dict[str, Any]:
        """Evaluate JavaScript in the current page."""
        return _run_cli("evaluate", script, tab=tab)

    @mcp.tool()
    def screenshot(path: str = DEFAULT_SCREENSHOT_PATH, tab: str = "") -> dict[str, Any]:
        """Capture a viewport screenshot as a PNG file."""
        return _run_cli("screenshot", "--out", path, timeout=60.0, tab=tab)

    @mcp.tool()
    def screenshot_full(path: str = DEFAULT_SCREENSHOT_PATH, tab: str = "") -> dict[str, Any]:
        """Capture a full-page screenshot if supported by the installed CLI."""
        return _run_cli("screenshot", "--full", "--out", path, timeout=120.0, tab=tab)

    @mcp.tool()
    def screenshot_element(selector: str, path: str = DEFAULT_SCREENSHOT_PATH, tab: str = "") -> dict[str, Any]:
        """Capture a screenshot clipped to a CSS selector or snapshot ref."""
        return _run_cli("screenshot-element", selector, "--out", path, timeout=60.0, tab=tab)

    @mcp.tool()
    def click(selector: str, native: bool = False, fallback: bool = True, tab: str = "") -> dict[str, Any]:
        """Click a CSS selector or snapshot ref; set native=True for native coordinate click and fallback=False to fail if native verification fails."""
        args = [selector]
        if native:
            args.append("--native")
        if not fallback:
            args.append("--no-fallback")
        return _run_cli("click", *args, tab=tab)

    @mcp.tool()
    def fill(selector: str, value: str, tab: str = "") -> dict[str, Any]:
        """Fill an input-like element matching a CSS selector or snapshot ref."""
        return _run_cli("fill", selector, value, tab=tab)

    @mcp.tool()
    def key(key: str, tab: str = "") -> dict[str, Any]:
        """Dispatch keydown/keypress/keyup for a key to the active element."""
        return _run_cli("key", key, tab=tab)

    @mcp.tool()
    def type_text(text: str, tab: str = "") -> dict[str, Any]:
        """Insert text into the active input, textarea, or contenteditable element."""
        return _run_cli("type", text, tab=tab)

    @mcp.tool()
    def wait(ms: int, tab: str = "") -> dict[str, Any]:
        """Sleep for the requested number of milliseconds in the daemon command queue."""
        return _run_cli("wait", str(ms), timeout=max(30.0, (float(ms) / 1000.0) + 5.0), tab=tab)

    @mcp.tool()
    def wait_for_selector(selector: str, timeout_ms: int = 10000, tab: str = "") -> dict[str, Any]:
        """Wait until a CSS selector exists in the current document."""
        return _run_cli("wait-for-selector", selector, "--timeout", str(timeout_ms), timeout=(float(timeout_ms) / 1000.0) + 5.0, tab=tab)

    @mcp.tool()
    def wait_for_text(text: str, timeout_ms: int = 10000, tab: str = "") -> dict[str, Any]:
        """Wait until document.body text contains the supplied text."""
        return _run_cli("wait-for-text", text, "--timeout", str(timeout_ms), timeout=(float(timeout_ms) / 1000.0) + 5.0, tab=tab)

    @mcp.tool()
    def wait_for_url(url: str, timeout_ms: int = 10000, tab: str = "") -> dict[str, Any]:
        """Wait until the current page URL contains the supplied substring."""
        return _run_cli("wait-for-url", url, "--timeout", str(timeout_ms), timeout=(float(timeout_ms) / 1000.0) + 5.0, tab=tab)

    @mcp.tool()
    def wait_for_title(title: str, timeout_ms: int = 10000, tab: str = "") -> dict[str, Any]:
        """Wait until the current document title contains the supplied substring."""
        return _run_cli("wait-for-title", title, "--timeout", str(timeout_ms), timeout=(float(timeout_ms) / 1000.0) + 5.0, tab=tab)

    @mcp.tool()
    def wait_for_visible(selector: str, timeout_ms: int = 10000, tab: str = "") -> dict[str, Any]:
        """Wait until a CSS selector exists and has a visible viewport-intersecting box."""
        return _run_cli("wait-for-visible", selector, "--timeout", str(timeout_ms), timeout=(float(timeout_ms) / 1000.0) + 5.0, tab=tab)

    @mcp.tool()
    def wait_for_idle(timeout_ms: int = 10000, tab: str = "") -> dict[str, Any]:
        """Wait until the page is loaded and observed fetch/XHR activity is idle."""
        return _run_cli("wait-for-idle", "--timeout", str(timeout_ms), timeout=(float(timeout_ms) / 1000.0) + 5.0, tab=tab)

    @mcp.tool()
    def network_start(tab: str = "") -> dict[str, Any]:
        """Start JavaScript fetch/XHR network capture instrumentation."""
        return _run_cli("network", "start", tab=tab)

    @mcp.tool()
    def network_list(tab: str = "") -> dict[str, Any]:
        """Return captured fetch/XHR network entries."""
        return _run_cli("network", "list", tab=tab)

    @mcp.tool()
    def network_stop(tab: str = "") -> dict[str, Any]:
        """Stop JavaScript fetch/XHR network capture instrumentation."""
        return _run_cli("network", "stop", tab=tab)

    @mcp.tool()
    def network_export(path: str, body_preview_bytes: int | None = None, max_entries: int | None = None, tab: str = "") -> dict[str, Any]:
        """Export captured fetch/XHR entries to a redacted JSON file."""
        args = ["export", path]
        if body_preview_bytes is not None:
            args.extend(["--body-preview-bytes", str(body_preview_bytes)])
        if max_entries is not None:
            args.extend(["--max-entries", str(max_entries)])
        return _run_cli("network", *args, tab=tab)

    @mcp.tool()
    def back(tab: str = "") -> dict[str, Any]:
        """Navigate back in WebKit history if possible."""
        return _run_cli("back", tab=tab)

    @mcp.tool()
    def forward(tab: str = "") -> dict[str, Any]:
        """Navigate forward in WebKit history if possible."""
        return _run_cli("forward", tab=tab)

    @mcp.tool()
    def reload(tab: str = "") -> dict[str, Any]:
        """Reload the current page."""
        return _run_cli("reload", tab=tab)

    @mcp.tool()
    def viewport(width: int, height: int, tab: str = "") -> dict[str, Any]:
        """Resize the controlled WebKit viewport/window."""
        return _run_cli("viewport", str(width), str(height), tab=tab)

    @mcp.tool()
    def session() -> dict[str, Any]:
        """Return the current automation session metadata."""
        return _run_cli("session")

    @mcp.tool()
    def tabs() -> dict[str, Any]:
        """List modeled tabs for the current daemon session."""
        return _run_cli("tabs")

    @mcp.tool()
    def tab_new(url: str | None = None) -> dict[str, Any]:
        """Create a new WebKit tab and optionally navigate it to a URL."""
        args = [url] if url else []
        return _run_cli("tab-new", *args, timeout=60.0 if url else 30.0)

    @mcp.tool()
    def tab_switch(tab_id: str) -> dict[str, Any]:
        """Switch to a modeled tab id."""
        return _run_cli("tab-switch", tab_id)

    @mcp.tool()
    def tab_close(tab_id: str) -> dict[str, Any]:
        """Close a modeled tab id when supported."""
        return _run_cli("tab-close", tab_id)

    @mcp.tool()
    def downloads() -> dict[str, Any]:
        """List downloads observed by this daemon session (daemon-wide, capped at 50)."""
        return _run_cli("downloads")

    @mcp.tool()
    def wait_for_download(download_id: str = "--last", timeout_ms: int = 10000) -> dict[str, Any]:
        """Wait until a download leaves the pending state; download_id may be an id or --last."""
        return _run_cli("wait-for-download", download_id, "--timeout", str(timeout_ms), timeout=(float(timeout_ms) / 1000.0) + 5.0)

    return mcp


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="MCP stdio server for the agent-safari CLI.",
        epilog=_help_text(),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate wrapper configuration without starting the MCP server",
    )
    parser.add_argument(
        "--tools-json",
        action="store_true",
        help="print the stable MCP tool contract as JSON and exit",
    )
    args = parser.parse_args(argv)

    if args.tools_json:
        print(json.dumps(TOOL_CONTRACTS, indent=2, sort_keys=True))
        return 0

    if args.check:
        binary = agent_safari_bin()
        print(f"AGENT_SAFARI_BIN={binary}")
        print(f"AGENT_SAFARI_SOCKET={agent_safari_socket()}")
        print(f"binary_exists={Path(binary).exists()}")
        return 0

    server = create_server()
    server.run(transport="stdio")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
