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


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def default_bin() -> str:
    return str(_repo_root() / ".build" / "debug" / "agent-safari")


def agent_safari_bin() -> str:
    return os.environ.get("AGENT_SAFARI_BIN", default_bin())


def agent_safari_socket() -> str:
    return os.environ.get("AGENT_SAFARI_SOCKET", DEFAULT_SOCKET)


def _run_cli(command: str, *args: str, timeout: float = 30.0) -> dict[str, Any]:
    """Run agent-safari CLI and return the decoded JSON-RPC response."""
    binary = agent_safari_bin()
    socket_path = agent_safari_socket()

    if not Path(binary).exists():
        raise RuntimeError(
            f"agent-safari binary not found at {binary!r}; build with `swift build` "
            "or set AGENT_SAFARI_BIN."
        )

    argv = [binary, command, *[str(arg) for arg in args], "--socket", socket_path]
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
        message = error.get("message") if isinstance(error, dict) else str(error)
        raise RuntimeError(f"agent-safari {command} error: {message or payload}")
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
    def status() -> dict[str, Any]:
        """Return daemon/page status for the controlled Safari WebView."""
        return _run_cli("status")

    @mcp.tool()
    def observe() -> dict[str, Any]:
        """Return read-only page state for agent loops."""
        return _run_cli("observe")

    @mcp.tool()
    def navigate(url: str) -> dict[str, Any]:
        """Navigate the controlled Safari WebView to a URL."""
        return _run_cli("navigate", url, timeout=60.0)

    @mcp.tool()
    def text() -> dict[str, Any]:
        """Return visible page text."""
        return _run_cli("text")

    @mcp.tool()
    def html() -> dict[str, Any]:
        """Return document.documentElement.outerHTML."""
        return _run_cli("html")

    @mcp.tool()
    def title() -> dict[str, Any]:
        """Return the current document title."""
        return _run_cli("title")

    @mcp.tool()
    def url() -> dict[str, Any]:
        """Return the current document URL."""
        return _run_cli("url")

    @mcp.tool()
    def content() -> dict[str, Any]:
        """Alias for visible page text."""
        return _run_cli("content")

    @mcp.tool()
    def snapshot() -> dict[str, Any]:
        """Return a JSON string snapshot of interactive elements."""
        return _run_cli("snapshot")

    @mcp.tool()
    def evaluate(script: str) -> dict[str, Any]:
        """Evaluate JavaScript in the current page."""
        return _run_cli("evaluate", script)

    @mcp.tool()
    def screenshot(path: str = DEFAULT_SCREENSHOT_PATH) -> dict[str, Any]:
        """Capture a viewport screenshot as a PNG file."""
        return _run_cli("screenshot", path, timeout=60.0)

    @mcp.tool()
    def screenshot_full(path: str = DEFAULT_SCREENSHOT_PATH) -> dict[str, Any]:
        """Capture a full-page screenshot if supported by the installed CLI."""
        return _run_cli("screenshot-full", path, timeout=120.0)

    @mcp.tool()
    def click(selector: str, native: bool = False, fallback: bool = True) -> dict[str, Any]:
        """Click a CSS selector or snapshot ref; set native=True for native coordinate click and fallback=False to fail if native verification fails."""
        args = [selector]
        if native:
            args.append("--native")
        if not fallback:
            args.append("--no-fallback")
        return _run_cli("click", *args)

    @mcp.tool()
    def fill(selector: str, value: str) -> dict[str, Any]:
        """Fill an input-like element matching a CSS selector or snapshot ref."""
        return _run_cli("fill", selector, value)

    @mcp.tool()
    def key(key: str) -> dict[str, Any]:
        """Dispatch keydown/keypress/keyup for a key to the active element."""
        return _run_cli("key", key)

    @mcp.tool()
    def type_text(text: str) -> dict[str, Any]:
        """Insert text into the active input, textarea, or contenteditable element."""
        return _run_cli("type", text)

    @mcp.tool()
    def wait(ms: int) -> dict[str, Any]:
        """Sleep for the requested number of milliseconds in the daemon command queue."""
        return _run_cli("wait", str(ms), timeout=max(30.0, (float(ms) / 1000.0) + 5.0))

    @mcp.tool()
    def wait_for_selector(selector: str, timeout_ms: int = 10000) -> dict[str, Any]:
        """Wait until a CSS selector exists in the current document."""
        return _run_cli("wait-for-selector", selector, "--timeout", str(timeout_ms), timeout=(float(timeout_ms) / 1000.0) + 5.0)

    @mcp.tool()
    def wait_for_text(text: str, timeout_ms: int = 10000) -> dict[str, Any]:
        """Wait until document.body text contains the supplied text."""
        return _run_cli("wait-for-text", text, "--timeout", str(timeout_ms), timeout=(float(timeout_ms) / 1000.0) + 5.0)

    @mcp.tool()
    def wait_for_idle(timeout_ms: int = 10000) -> dict[str, Any]:
        """Wait until the page is loaded and observed fetch/XHR activity is idle."""
        return _run_cli("wait-for-idle", "--timeout", str(timeout_ms), timeout=(float(timeout_ms) / 1000.0) + 5.0)

    @mcp.tool()
    def network_start() -> dict[str, Any]:
        """Start JavaScript fetch/XHR network capture instrumentation."""
        return _run_cli("network-start")

    @mcp.tool()
    def network_list() -> dict[str, Any]:
        """Return captured fetch/XHR network entries."""
        return _run_cli("network-list")

    @mcp.tool()
    def network_stop() -> dict[str, Any]:
        """Stop JavaScript fetch/XHR network capture instrumentation."""
        return _run_cli("network-stop")

    @mcp.tool()
    def network_export(path: str, body_preview_bytes: int | None = None, max_entries: int | None = None) -> dict[str, Any]:
        """Export captured fetch/XHR entries to a redacted JSON file."""
        args = [path]
        if body_preview_bytes is not None:
            args.extend(["--body-preview-bytes", str(body_preview_bytes)])
        if max_entries is not None:
            args.extend(["--max-entries", str(max_entries)])
        return _run_cli("network-export", *args)

    @mcp.tool()
    def back() -> dict[str, Any]:
        """Navigate back in WebKit history if possible."""
        return _run_cli("back")

    @mcp.tool()
    def forward() -> dict[str, Any]:
        """Navigate forward in WebKit history if possible."""
        return _run_cli("forward")

    @mcp.tool()
    def reload() -> dict[str, Any]:
        """Reload the current page."""
        return _run_cli("reload")

    @mcp.tool()
    def viewport(width: int, height: int) -> dict[str, Any]:
        """Resize the controlled WebKit viewport/window."""
        return _run_cli("viewport", str(width), str(height))

    @mcp.tool()
    def session() -> dict[str, Any]:
        """Return the current automation session metadata."""
        return _run_cli("session")

    @mcp.tool()
    def tabs() -> dict[str, Any]:
        """List modeled tabs for the current daemon session."""
        return _run_cli("tabs")

    @mcp.tool()
    def tab_new() -> dict[str, Any]:
        """Create or report the current tab placeholder in the single-WebView MVP."""
        return _run_cli("tab-new")

    @mcp.tool()
    def tab_switch(tab_id: str) -> dict[str, Any]:
        """Switch to a modeled tab id."""
        return _run_cli("tab-switch", tab_id)

    @mcp.tool()
    def tab_close(tab_id: str) -> dict[str, Any]:
        """Close a modeled tab id when supported."""
        return _run_cli("tab-close", tab_id)

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
    args = parser.parse_args(argv)

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
