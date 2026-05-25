#!/usr/bin/env python3
"""Detect local AI agents and optionally register the agent-safari MCP server.

This helper is intentionally consent-first. Homebrew can install it, but it only
writes agent configuration after an explicit yes from the user or --yes.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SERVER_NAME = "agent-safari"
DEFAULT_SOCKET = "/tmp/agent-safari.sock"


@dataclass(frozen=True)
class AgentTarget:
    key: str
    label: str
    path: Path
    kind: str  # json_mcp_servers or hermes_yaml
    detected: bool
    reason: str


def _home() -> Path:
    return Path(os.environ.get("HOME", str(Path.home()))).expanduser()


def _existing_or_parent(path: Path) -> bool:
    return path.exists() or path.parent.exists()


def detect_agents() -> list[AgentTarget]:
    home = _home()
    candidates = [
        AgentTarget(
            "claude-desktop",
            "Claude Desktop",
            home / "Library/Application Support/Claude/claude_desktop_config.json",
            "json_mcp_servers",
            _existing_or_parent(home / "Library/Application Support/Claude/claude_desktop_config.json"),
            "Claude config directory or config file exists",
        ),
        AgentTarget(
            "cursor",
            "Cursor",
            home / ".cursor/mcp.json",
            "json_mcp_servers",
            _existing_or_parent(home / ".cursor/mcp.json"),
            "Cursor MCP config directory or config file exists",
        ),
        AgentTarget(
            "windsurf",
            "Windsurf",
            home / ".codeium/windsurf/mcp_config.json",
            "json_mcp_servers",
            _existing_or_parent(home / ".codeium/windsurf/mcp_config.json"),
            "Windsurf MCP config directory or config file exists",
        ),
        AgentTarget(
            "vscode",
            "VS Code",
            home / "Library/Application Support/Code/User/mcp.json",
            "json_mcp_servers",
            _existing_or_parent(home / "Library/Application Support/Code/User/mcp.json"),
            "VS Code user config directory or MCP config file exists",
        ),
        AgentTarget(
            "hermes",
            "Hermes Agent",
            home / ".hermes/config.yaml",
            "hermes_yaml",
            (home / ".hermes").exists() or shutil.which("hermes") is not None,
            "~/.hermes exists or hermes is on PATH",
        ),
    ]
    return [candidate for candidate in candidates if candidate.detected]


def resolve_wrapper_path(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).expanduser().resolve()
    env_path = os.environ.get("AGENT_SAFARI_MCP_WRAPPER")
    if env_path:
        return Path(env_path).expanduser().resolve()

    script = Path(__file__).resolve()
    candidates = [
        script.parent.parent / "mcp/agent_safari_mcp.py",
        script.parent.parent / "share/agent-safari/mcp/agent_safari_mcp.py",
        Path.cwd() / "mcp/agent_safari_mcp.py",
    ]

    brew = shutil.which("brew")
    if brew:
        try:
            result = subprocess.run(
                [brew, "--prefix", "agent-safari"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=10,
            )
            if result.returncode == 0 and result.stdout.strip():
                candidates.append(Path(result.stdout.strip()) / "mcp/agent_safari_mcp.py")
        except (OSError, subprocess.SubprocessError):
            pass

    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()

    # Stable fallback for Homebrew even when formula is not installed in tests.
    return (script.parent.parent / "mcp/agent_safari_mcp.py").resolve()


def resolve_agent_safari_bin(explicit: str | None) -> str:
    if explicit:
        return str(Path(explicit).expanduser())
    env_path = os.environ.get("AGENT_SAFARI_BIN")
    if env_path:
        return env_path
    found = shutil.which("agent-safari")
    return found or "agent-safari"


def server_config(wrapper: Path, binary: str, socket: str, python: str) -> dict[str, Any]:
    return {
        "command": python,
        "args": [str(wrapper)],
        "env": {
            "AGENT_SAFARI_BIN": binary,
            "AGENT_SAFARI_SOCKET": socket,
        },
    }


def load_json_config(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise RuntimeError(f"invalid JSON in {path}: {error}") from error
    if not isinstance(data, dict):
        raise RuntimeError(f"expected a JSON object in {path}")
    return data


def write_json_target(path: Path, config: dict[str, Any], dry_run: bool) -> str:
    data = load_json_config(path)
    servers = data.setdefault("mcpServers", {})
    if not isinstance(servers, dict):
        raise RuntimeError(f"expected object at {path}: mcpServers")
    changed = servers.get(SERVER_NAME) != config
    servers[SERVER_NAME] = config
    if dry_run:
        return "would update" if changed else "already configured"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return "updated" if changed else "already configured"


def yaml_block(config: dict[str, Any]) -> str:
    args = config["args"]
    env = config["env"]
    return (
        f"  {SERVER_NAME}:\n"
        f"    command: {json.dumps(config['command'])}\n"
        f"    args: [{', '.join(json.dumps(item) for item in args)}]\n"
        f"    env:\n"
        f"      AGENT_SAFARI_BIN: {json.dumps(env['AGENT_SAFARI_BIN'])}\n"
        f"      AGENT_SAFARI_SOCKET: {json.dumps(env['AGENT_SAFARI_SOCKET'])}\n"
    )


def write_hermes_yaml(path: Path, config: dict[str, Any], dry_run: bool) -> str:
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    if f"\n  {SERVER_NAME}:" in f"\n{text}" or f"\n{SERVER_NAME}:" in f"\n{text}":
        return "already configured"

    addition = yaml_block(config)
    if "mcp_servers:" in text:
        new_text = text.rstrip() + "\n" + addition
    else:
        prefix = text.rstrip() + "\n\n" if text.strip() else ""
        new_text = prefix + "mcp_servers:\n" + addition

    if dry_run:
        return "would update"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(new_text, encoding="utf-8")
    return "updated"


def prompt_yes_no(question: str) -> bool:
    if not sys.stdin.isatty():
        return False
    answer = input(f"{question} [y/N] ").strip().lower()
    return answer in {"y", "yes"}


def install_target(target: AgentTarget, config: dict[str, Any], dry_run: bool) -> str:
    if target.kind == "json_mcp_servers":
        return write_json_target(target.path, config, dry_run)
    if target.kind == "hermes_yaml":
        return write_hermes_yaml(target.path, config, dry_run)
    raise RuntimeError(f"unknown target kind: {target.kind}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Register agent-safari MCP with detected local AI agents")
    parser.add_argument("--yes", "-y", action="store_true", help="apply to all selected agents without prompting")
    parser.add_argument("--dry-run", action="store_true", help="show what would be changed without writing files")
    parser.add_argument("--list", action="store_true", help="list detected agents and exit")
    parser.add_argument("--agent", action="append", choices=["claude-desktop", "cursor", "windsurf", "vscode", "hermes"], help="limit setup to one agent; repeatable")
    parser.add_argument("--wrapper", help="path to mcp/agent_safari_mcp.py")
    parser.add_argument("--bin", dest="binary", help="path to agent-safari binary")
    parser.add_argument("--socket", default=os.environ.get("AGENT_SAFARI_SOCKET", DEFAULT_SOCKET), help=f"daemon socket path (default: {DEFAULT_SOCKET})")
    parser.add_argument("--python", default=os.environ.get("AGENT_SAFARI_MCP_PYTHON", "python3"), help="Python executable for the MCP wrapper")
    args = parser.parse_args(argv)

    targets = detect_agents()
    if args.agent:
        selected = set(args.agent)
        targets = [target for target in targets if target.key in selected]

    if not targets:
        print("No supported AI agent config directories were detected.")
        print("Supported targets: Claude Desktop, Cursor, Windsurf, VS Code, Hermes Agent.")
        return 0

    wrapper = resolve_wrapper_path(args.wrapper)
    binary = resolve_agent_safari_bin(args.binary)
    config = server_config(wrapper, binary, args.socket, args.python)

    print("Detected AI agents:")
    for target in targets:
        print(f"- {target.label}: {target.path}")

    if args.list:
        return 0

    print("\nMCP server to register:")
    print(json.dumps({SERVER_NAME: config}, indent=2, sort_keys=True))
    print("\nThe daemon still needs to be started separately, for example:")
    print(f"  agent-safari daemon --socket {args.socket}")

    wrote_any = False
    for target in targets:
        approved = args.yes or args.dry_run or prompt_yes_no(f"Register agent-safari MCP with {target.label}?")
        if not approved:
            print(f"skipped {target.label}")
            continue
        try:
            status = install_target(target, config, args.dry_run)
        except Exception as error:  # noqa: BLE001 - CLI should keep processing other agents.
            print(f"error {target.label}: {error}", file=sys.stderr)
            continue
        wrote_any = wrote_any or status in {"updated", "would update"}
        print(f"{status} {target.label}: {target.path}")

    if not wrote_any and not args.dry_run:
        print("No config files were changed.")
    elif args.dry_run:
        print("Dry run only; no config files were changed.")
    else:
        print("Done. Restart or reload the selected agent(s) so they pick up the MCP server.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
