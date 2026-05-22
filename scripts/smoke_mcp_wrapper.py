#!/usr/bin/env python3
"""Smoke test the MCP wrapper's CLI bridge without importing the MCP SDK.

This script expects an agent-safari daemon to already be running. It imports
`_run_cli` from mcp/agent_safari_mcp.py, then exercises CLI-backed operations
through the same helper used by MCP tools.

Environment:
  AGENT_SAFARI_BIN       Path to built agent-safari binary.
  AGENT_SAFARI_SOCKET    Unix socket for the running daemon.
  AGENT_SAFARI_SMOKE_DIR Optional artifact directory.
"""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MCP_DIR = ROOT / "mcp"
if str(MCP_DIR) not in sys.path:
    sys.path.insert(0, str(MCP_DIR))

from agent_safari_mcp import _run_cli  # noqa: E402


def file_url(path: Path) -> str:
    return path.resolve().as_uri()


def daemon_available() -> bool:
    try:
        status = _run_cli("status", timeout=10.0)
    except RuntimeError as exc:
        print(f"[smoke_mcp_wrapper] daemon unavailable; skipping bridge smoke: {exc}")
        return False

    if not isinstance(status, dict):
        raise RuntimeError(f"status did not return an object: {status}")
    print(f"[smoke_mcp_wrapper] status ok: {status}")
    return True


def main() -> int:
    smoke_dir = Path(os.environ.get("AGENT_SAFARI_SMOKE_DIR", tempfile.mkdtemp(prefix="agent-safari-mcp-smoke.")))
    smoke_dir.mkdir(parents=True, exist_ok=True)
    html = smoke_dir / "mcp-smoke.html"
    screenshot = smoke_dir / "mcp-full-page.png"

    html.write_text(
        """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>agent-safari MCP smoke</title>
  <style>body{font-family:sans-serif;margin:32px}main{min-height:1400px}</style>
</head>
<body>
  <main>
    <h1 id="title">agent-safari MCP smoke</h1>
    <p id="status">ready</p>
  </main>
</body>
</html>
""",
        encoding="utf-8",
    )

    print(f"[smoke_mcp_wrapper] using binary: {os.environ.get('AGENT_SAFARI_BIN', '<wrapper default>')}")
    print(f"[smoke_mcp_wrapper] using socket: {os.environ.get('AGENT_SAFARI_SOCKET', '<wrapper default>')}")

    if not daemon_available():
        return 0

    network_started = False
    try:
        network_start = _run_cli("network-start")
        if not isinstance(network_start, dict):
            raise RuntimeError(f"network-start did not return an object: {network_start}")
        network_started = True
        print(f"[smoke_mcp_wrapper] network-start ok: {network_start}")

        nav = _run_cli("navigate", file_url(html), timeout=60.0)
        if "url" not in nav:
            raise RuntimeError(f"navigate did not return url: {nav}")

        observed = _run_cli("observe")
        for key in ("url", "title", "readyState", "isLoading", "networkCapturing", "activeElementTag"):
            if key not in observed:
                raise RuntimeError(f"observe missing {key}: {observed}")
        print(f"[smoke_mcp_wrapper] observe ok: {observed}")

        evaluated = _run_cli("evaluate", "document.getElementById('title').textContent")
        if evaluated.get("value") != "agent-safari MCP smoke":
            raise RuntimeError(f"unexpected evaluate value: {evaluated}")

        network_list = _run_cli("network-list")
        if not isinstance(network_list, dict):
            raise RuntimeError(f"network-list did not return an object: {network_list}")
        print(f"[smoke_mcp_wrapper] network-list ok: {network_list}")

        shot = _run_cli("screenshot-full", str(screenshot), timeout=120.0)
        shot_path = Path(shot.get("path", str(screenshot)))
        if not shot_path.exists() or shot_path.stat().st_size == 0:
            raise RuntimeError(f"screenshot was not written or is empty: {shot_path}")
    finally:
        if network_started:
            try:
                network_stop = _run_cli("network-stop")
                print(f"[smoke_mcp_wrapper] network-stop ok: {network_stop}")
            except RuntimeError as exc:
                print(f"[smoke_mcp_wrapper] warning: network-stop failed: {exc}")

    print("[smoke_mcp_wrapper] ok")
    print(f"[smoke_mcp_wrapper] artifacts: {smoke_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
