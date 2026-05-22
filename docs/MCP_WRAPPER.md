# agent-safari MCP wrapper

This project includes a lightweight Python MCP stdio server that wraps the built
`agent-safari` CLI. The Swift CLI continues to talk to the running Safari/WebKit
daemon over a Unix socket; the MCP layer only translates MCP tool calls into CLI
commands.

## Files

- `mcp/agent_safari_mcp.py` - MCP stdio server wrapper.
- `mcp/requirements.txt` - Python dependency for the MCP SDK.

## Prerequisites

1. Build the CLI:

   ```sh
   swift build
   ```

2. Install the Python MCP SDK into the project-local virtual environment:

   ```sh
   python3 -m venv .venv-mcp
   .venv-mcp/bin/python -m pip install -r mcp/requirements.txt
   ```

3. Start the agent-safari daemon in another terminal:

   ```sh
   .build/debug/agent-safari daemon --socket /tmp/agent-safari.sock
   ```

   Autostarting the daemon from the MCP wrapper is intentionally left as a future
   TODO so the wrapper does not unexpectedly launch GUI/browser state.

## Configuration

The wrapper uses these defaults:

- CLI binary: `.build/debug/agent-safari` relative to the repository root
- Socket: `/tmp/agent-safari.sock`

Override them with environment variables:

- `AGENT_SAFARI_BIN`
- `AGENT_SAFARI_SOCKET`

## Hermes config example

Add an entry under `mcp_servers` (or run the `hermes mcp add` command below):

```yaml
mcp_servers:
  agent-safari:
    command: "<repo>/agent-safari/.venv-mcp/bin/python"
    args: ["<repo>/agent-safari/mcp/agent_safari_mcp.py"]
    env:
      AGENT_SAFARI_BIN: "<repo>/agent-safari/.build/debug/agent-safari"
      AGENT_SAFARI_SOCKET: "/tmp/agent-safari.sock"
```

Equivalent Hermes CLI command:

```sh
hermes mcp add agent-safari \
  --command "$PWD/.venv-mcp/bin/python" \
  --args "$PWD/mcp/agent_safari_mcp.py" \
  --env AGENT_SAFARI_BIN="$PWD/.build/debug/agent-safari" AGENT_SAFARI_SOCKET=/tmp/agent-safari.sock
```

## Exposed tools

- `status()`
- `observe()`
- `navigate(url)`
- `text()`
- `html()`
- `title()`
- `url()`
- `content()`
- `snapshot()`
- `evaluate(script)`
- `screenshot(path)`
- `screenshot_full(path)` if supported by the installed CLI
- `click(selector, native=False, fallback=True)`
- `fill(selector, value)`
- `key(key)`
- `type_text(text)`
- `wait(ms)`
- `wait_for_selector(selector, timeout_ms=10000)`
- `wait_for_text(text, timeout_ms=10000)`
- `wait_for_idle(timeout_ms=10000)`
- `network_start()`
- `network_list()`
- `network_stop()`
- `network_export(path, body_preview_bytes=None, max_entries=None)`
- `back()`
- `forward()`
- `reload()`
- `viewport(width, height)`
- `session()`
- `tabs()`
- `tab_new()`
- `tab_switch(tab_id)`
- `tab_close(tab_id)`

Most tools return the CLI result object decoded from the JSON-RPC response. For
example, `text()` returns an object like `{ "text": "..." }`.

## Local checks

```sh
python3 -m py_compile mcp/agent_safari_mcp.py
python3 mcp/agent_safari_mcp.py --check
python3 mcp/agent_safari_mcp.py --help
```

If you installed the MCP SDK into `.venv-mcp`, replace `python3` with
`.venv-mcp/bin/python` for runtime checks. `--check` validates paths and prints
the effective binary/socket configuration; it does not connect to the daemon.

## MCP bridge smoke without the MCP SDK

`scripts/smoke_mcp_wrapper.py` imports `_run_cli` from this wrapper and exercises
the same CLI bridge used by the MCP tools. It intentionally does not import or
start the MCP SDK.

Start a daemon first:

```sh
swift build
.build/debug/agent-safari daemon --socket /tmp/agent-safari.sock
```

Then run the smoke in another terminal:

```sh
AGENT_SAFARI_BIN="$PWD/.build/debug/agent-safari" \
AGENT_SAFARI_SOCKET=/tmp/agent-safari.sock \
python3 scripts/smoke_mcp_wrapper.py
```

The smoke creates a local HTML file, verifies `status`, starts network capture,
navigates to the page, calls `evaluate`, checks `observe`, checks `network-list`, captures
`screenshot-full`, verifies the screenshot file is non-empty, and stops network
capture in cleanup. If no daemon is reachable, the smoke reports that and exits
successfully so syntax-only environments remain robust.
