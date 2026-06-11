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

## Consent-first host registration

Homebrew and source installs include `agent-safari-mcp-setup`. Run it after install to detect local MCP-capable agents and approve each config write:

```sh
agent-safari-mcp-setup --dry-run
agent-safari-mcp-setup
```

The helper supports Claude Desktop, Cursor, Windsurf, VS Code, and Hermes Agent. It writes standard `mcpServers` JSON for JSON-based clients and `mcp_servers` YAML for Hermes.

## Configuration

The wrapper uses these defaults:

- CLI binary: `.build/debug/agent-safari` relative to the repository root
- Socket: `/tmp/agent-safari.sock`

Override them with environment variables:

- `AGENT_SAFARI_BIN`
- `AGENT_SAFARI_SOCKET`

## Action result contract

The MCP wrapper mirrors CLI result fields instead of inventing a separate browser protocol. `click` advertises native/fallback metadata (`method`, `nativeVerified`, `fallbackUsed`, `nativeError`, `nativeErrorCode`, and `popupRedirectedURL` when a popup or `target=_blank` navigation was intercepted) plus viewport, bounds, scroll, and coordinate fields emitted by the Swift daemon. `fill` returns `selector` and `value`, matching the CLI. `click` and `evaluate` accept an optional `confirm` input (`accept`|`dismiss`, default `dismiss`) that controls how suppressed JS `confirm()` dialogs are answered, and `click` reports any suppressed `alert`/`confirm`/`prompt` dialogs as a `suppressedDialogs` JSON array. Failed CLI payloads preserve the daemon's stable `error.code` in the wrapper exception message and `AgentSafariCLIError.code`.

Downloads are surfaced as evidence rather than a separate protocol: a `navigate` or `click` that triggers a download reports `downloadStarted`/`downloadId`, and `downloads()` plus `wait_for_download(download_id, timeout_ms)` expose the daemon-wide download log written under `~/.agent-safari/downloads/<id>/<filename>` (see `docs/CLI_USAGE.md` for states, the 50-entry cap, and the `unknown_download` error code).

Page-level tools accept an optional `tab` input that maps to the CLI's global `--tab <id>` option: the command targets that modeled tab without switching the active tab, commands on different tabs run concurrently, and every result reports the `tabId` it acted on. Tabs share one window and one cookie/data store; per-tab limits and error codes (`unknown_tab`, `navigation_in_progress`, `tab_closed_during_command`, `tab_not_active_for_native_input`) are documented in `docs/CLI_USAGE.md`.
The `cookies_export` and `cookies_import` tools export/import session cookies from the daemon's `WKWebsiteDataStore` to a JSON file; cookies are session-wide (shared across all tabs) and the exported file is written with `0600` permissions. Page-level tools accept an optional `tab` input that maps to the CLI's global `--tab <id>` option: the command targets that modeled tab without switching the active tab, commands on different tabs run concurrently, and every result reports the `tabId` it acted on. Tabs share one window and one cookie/data store; per-tab limits and error codes (`unknown_tab`, `navigation_in_progress`, `tab_closed_during_command`, `tab_not_active_for_native_input`) are documented in `docs/CLI_USAGE.md`.

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
- `screenshot_element(selector, path)`
- `click(selector, native=False, fallback=True)`
- `fill(selector, value)`
- `upload(selector, paths)` set files on an `<input type=file>`; pass multiple paths only when the input has the `multiple` attribute
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
- `console_start()` — JavaScript console.error/warn and page-error instrumentation (not full DevTools console)
- `console_list()`
- `console_stop()`
- `back()`
- `forward()`
- `reload()`
- `viewport(width, height)`
- `session()`
- `tabs()`
- `tab_new(url=None)`
- `tab_switch(tab_id)`
- `tab_close(tab_id)`
- `downloads()`
- `wait_for_download(download_id="--last", timeout_ms=10000)`
- `session_snapshot(path)` — dump full session state as a JSON artifact for failure reports

Most tools return the CLI result object decoded from the JSON-RPC response. For
example, `text()` returns an object like `{ "text": "..." }`. The wrapper also
publishes a machine-readable contract for tests, agents, and docs:

```sh
python3 mcp/agent_safari_mcp.py --tools-json
```

That JSON lists each tool name, short description, normalized CLI equivalent,
input names, `contractVersion`, and expected top-level result keys. CI locks this
with `Tests/test_mcp_contract.py`.

Session and tab tools are socket-scoped because the MCP wrapper delegates to the
CLI. `session()` reports the daemon's current `sessionId`, active tab, profile
metadata, persistence mode, data store mode, and tab count. `tabs()` returns the
modeled tab list for that daemon. Multiple independent MCP browser sessions
require multiple daemon processes with separate sockets.

## Local checks

```sh
python3 -m py_compile mcp/agent_safari_mcp.py
python3 mcp/agent_safari_mcp.py --check
python3 mcp/agent_safari_mcp.py --tools-json
python3 mcp/agent_safari_mcp.py --help
python3 Tests/test_mcp_contract.py
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
