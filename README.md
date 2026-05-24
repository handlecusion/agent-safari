# agent-safari

`agent-safari` is a Swift command-line tool, local daemon, and MCP stdio server for driving a native Safari/WebKit browser window over a Unix domain socket.

The intended control loop is:

```text
daemon -> navigate -> snapshot -> act on @e refs -> capture/evaluate/network inspect
```

It can be used directly from shell scripts via the CLI, or from Hermes/other MCP clients via the Python MCP wrapper.

## Requirements

- macOS with GUI access
- Swift toolchain
- Python 3 for the MCP wrapper
- Optional but recommended: local MCP venv at `.venv-mcp`

## Quick start: CLI

Build the Swift binary and install a convenient `agent-safari` command into `~/.local/bin`:

```sh
git clone https://github.com/handlecusion/agent-safari.git agent-safari
cd agent-safari
scripts/install_cli.sh
```

The installer builds the package and creates this symlink:

```text
~/.local/bin/agent-safari -> <repo>/agent-safari/.build/debug/agent-safari
```

If `~/.local/bin` is on your PATH, after installation you can use `agent-safari` directly instead of typing `.build/debug/agent-safari`.

Start the WebKit daemon:

```sh
agent-safari daemon --socket /tmp/agent-safari.sock
```

By default the window is shown without stealing keyboard focus from your current app. If you want the browser to come to the front and become focused at startup, add `--focus-window`.

For development, rebuild, reinstall, stop any existing daemon, and start a fresh daemon in one command:

```sh
scripts/dev_restart.sh
```

Optionally navigate immediately after restart:

```sh
scripts/dev_restart.sh 'https://www.google.com'
```

By default this uses `/tmp/agent-safari.sock`, writes logs to `.tmp/agent-safari-daemon.log`, and stores the daemon PID at `.tmp/agent-safari-daemon.pid`. You can override the socket with `AGENT_SAFARI_SOCKET=/tmp/custom.sock scripts/dev_restart.sh`.

In another terminal, control it:

```sh
agent-safari open 'https://example.com' --socket /tmp/agent-safari.sock
agent-safari text --socket /tmp/agent-safari.sock
agent-safari snapshot --socket /tmp/agent-safari.sock
agent-safari screenshot --full --out /tmp/agent-safari-full.png --socket /tmp/agent-safari.sock
agent-safari screenshot-element '@e1' --out /tmp/agent-safari-element.png --socket /tmp/agent-safari.sock
```

The daemon opens a native WebKit window. CLI commands print one JSON response line. Successful responses have `"ok": true` and a `result` object.

## CLI command reference

All client commands accept `--socket <path>`. Default socket path is `/tmp/agent-safari.sock`.

```sh
agent-safari daemon [--focus-window] [--profile <name>] [--ephemeral] [--socket /tmp/agent-safari.sock]
agent-safari status [--socket /tmp/agent-safari.sock]
agent-safari observe [--socket /tmp/agent-safari.sock]
agent-safari open <url> [--socket /tmp/agent-safari.sock]
agent-safari navigate <url> [--socket /tmp/agent-safari.sock]  # backward-compatible alias
agent-safari text [--socket /tmp/agent-safari.sock]
agent-safari html [--socket /tmp/agent-safari.sock]
agent-safari snapshot [--socket /tmp/agent-safari.sock]
agent-safari evaluate <javascript> [--socket /tmp/agent-safari.sock]
agent-safari screenshot --out <path> [--socket /tmp/agent-safari.sock]
agent-safari screenshot --full --out <path> [--socket /tmp/agent-safari.sock]
agent-safari screenshot-element <selector-or-ref> --out <path> [--socket /tmp/agent-safari.sock]
agent-safari screenshot --element <selector-or-ref> --out <path> [--socket /tmp/agent-safari.sock]
agent-safari screenshot-full <path> [--socket /tmp/agent-safari.sock]  # backward-compatible alias
agent-safari click <selector-or-ref> [--native] [--socket /tmp/agent-safari.sock]
agent-safari fill <selector-or-ref> <value> [--socket /tmp/agent-safari.sock]
agent-safari key <key> [--socket /tmp/agent-safari.sock]
agent-safari type <text> [--socket /tmp/agent-safari.sock]
agent-safari wait <ms> [--socket /tmp/agent-safari.sock]
agent-safari wait-for-selector <selector> [--timeout <ms>] [--socket /tmp/agent-safari.sock]
agent-safari wait-for-text <text> [--timeout <ms>] [--socket /tmp/agent-safari.sock]
agent-safari wait-for-idle [--timeout <ms>] [--socket /tmp/agent-safari.sock]
agent-safari network start [--socket /tmp/agent-safari.sock]
agent-safari network list [--socket /tmp/agent-safari.sock]
agent-safari network stop [--socket /tmp/agent-safari.sock]
agent-safari network export <path> [--body-preview-bytes <n>] [--max-entries <n>] [--socket /tmp/agent-safari.sock]
agent-safari network-start [--socket /tmp/agent-safari.sock]  # backward-compatible alias
agent-safari network-list [--socket /tmp/agent-safari.sock]
agent-safari network-stop [--socket /tmp/agent-safari.sock]
```

### Agentic refs workflow

`snapshot` returns visible/interactable elements with stable refs like `@e1`, `@e2`, ... . You can pass those refs back to `click` and `fill`.

Example:

```sh
agent-safari open 'https://example.com' --socket /tmp/agent-safari.sock
agent-safari snapshot --socket /tmp/agent-safari.sock
agent-safari click '@e1' --native --socket /tmp/agent-safari.sock
agent-safari fill '@e2' 'hello@example.com' --socket /tmp/agent-safari.sock
agent-safari type ' extra text' --socket /tmp/agent-safari.sock
```

CSS selectors still work:

```sh
agent-safari click 'button[type="submit"]' --socket /tmp/agent-safari.sock
agent-safari fill 'input[name="email"]' 'hello@example.com' --socket /tmp/agent-safari.sock
```

### Wait commands

Wait commands help coordinate navigation, DOM changes, and asynchronous page work:

```sh
agent-safari wait 500 --socket /tmp/agent-safari.sock
agent-safari wait-for-selector '#results' --timeout 10000 --socket /tmp/agent-safari.sock
agent-safari wait-for-text 'Loaded' --timeout 10000 --socket /tmp/agent-safari.sock
agent-safari wait-for-idle --timeout 10000 --socket /tmp/agent-safari.sock
```

`wait-for-selector`, `wait-for-text`, and `wait-for-idle` default to a 10 second timeout. `wait-for-idle` waits for `document.readyState == "complete"`, no active WebKit load, and no pending fetch/XHR requests tracked by the optional network instrumentation.

### Screenshots

Viewport screenshot:

```sh
agent-safari screenshot --out /tmp/viewport.png --socket /tmp/agent-safari.sock
```

Full-page screenshot:

```sh
agent-safari screenshot --full --out /tmp/full-page.png --socket /tmp/agent-safari.sock
```

`screenshot-full` uses single-rect capture for modest pages and tiled scroll/stitching for large vertical pages.

### Network capture

Network capture is an MVP implemented by injected JavaScript instrumentation for `fetch` and `XMLHttpRequest`.

```sh
agent-safari network start --socket /tmp/agent-safari.sock
agent-safari open 'http://127.0.0.1:9876/index.html' --socket /tmp/agent-safari.sock
agent-safari network list --socket /tmp/agent-safari.sock
agent-safari network stop --socket /tmp/agent-safari.sock
```

Limitations:

- Captures fetch/XHR metadata.
- Does not capture parser-driven resources such as images/CSS as a full browser network tab would.
- Does not yet implement proxy-grade HAR export, WebSocket frame capture, or service-worker-level capture.

## MCP usage

See also:

- `docs/AGENT_LOOP.md` for the observe -> act -> wait -> verify browser-agent loop.
- `docs/PROFILE_PERSISTENCE.md` for profile, cookie, and session persistence behavior.

The MCP server is a Python stdio wrapper around the Swift CLI:

```text
MCP client -> mcp/agent_safari_mcp.py -> agent-safari -> Unix socket daemon -> WKWebView
```

The daemon must be running before MCP tools can control the browser:

```sh
git clone https://github.com/handlecusion/agent-safari.git agent-safari
cd agent-safari
scripts/install_cli.sh
agent-safari daemon --socket /tmp/agent-safari.sock
```

### MCP environment variables

```sh
export AGENT_SAFARI_BIN="$PWD/.build/debug/agent-safari"
export AGENT_SAFARI_SOCKET=/tmp/agent-safari.sock
```

### MCP wrapper health check

Using the project venv:

```sh
.venv-mcp/bin/python mcp/agent_safari_mcp.py --check
```

Expected output includes:

```text
AGENT_SAFARI_BIN=<repo>/agent-safari/.build/debug/agent-safari
AGENT_SAFARI_SOCKET=/tmp/agent-safari.sock
binary_exists=True
```

### Hermes MCP registration

This project has been verified with Hermes using an MCP server named `agent-safari`.

Add/register manually if needed:

```sh
hermes mcp add agent-safari \
  --command "$PWD/.venv-mcp/bin/python" \
  --args "$PWD/mcp/agent_safari_mcp.py" \
  --env AGENT_SAFARI_BIN="$PWD/.build/debug/agent-safari" \
  --env AGENT_SAFARI_SOCKET=/tmp/agent-safari.sock
```

Verify:

```sh
hermes mcp list
hermes mcp test agent-safari
```

After changing MCP config in an active Hermes session, reload MCP servers with `/reload-mcp` or start a fresh session.

### MCP tools currently exposed

The MCP wrapper currently exposes these tools:

| Tool | Purpose | CLI equivalent |
| --- | --- | --- |
| `status()` | Return daemon/page status for the controlled WebView. | `agent-safari status` |
| `observe()` | Return read-only URL/title/load/network/active-element state for agent loops. | `agent-safari observe` |
| `navigate(url)` | Navigate the controlled WebView to a URL. | `agent-safari navigate <url>` |
| `text()` | Return visible page text. | `agent-safari text` |
| `html()` | Return `document.documentElement.outerHTML`. | `agent-safari html` |
| `title()` | Return the current document title. | `agent-safari title` |
| `url()` | Return the current document URL. | `agent-safari url` |
| `content()` | Alias for visible page text. | `agent-safari content` |
| `snapshot()` | Return JSON string of visible/interactable elements and `@e` refs. | `agent-safari snapshot` |
| `evaluate(script)` | Evaluate JavaScript and return its stringified value. | `agent-safari evaluate <js>` |
| `screenshot(path)` | Capture viewport PNG. | `agent-safari screenshot <path>` |
| `screenshot_full(path)` | Capture full-page PNG. | `agent-safari screenshot-full <path>` |
| `click(selector, native=False)` | Click CSS selector or snapshot ref such as `@e1`; optional native coordinate click. | `agent-safari click <selector-or-ref> [--native]` |
| `fill(selector, value)` | Fill CSS selector or snapshot ref. | `agent-safari fill <selector-or-ref> <value>` |
| `key(key)` | Dispatch synthetic DOM keyboard events. | `agent-safari key <key>` |
| `type_text(text)` | Insert text into the active input/textarea/contenteditable. | `agent-safari type <text>` |
| `wait(ms)` | Wait for a number of milliseconds. | `agent-safari wait <ms>` |
| `wait_for_selector(selector, timeout_ms=10000)` | Wait for a selector to appear. | `agent-safari wait-for-selector <selector> --timeout <ms>` |
| `wait_for_text(text, timeout_ms=10000)` | Wait for page text to contain a string. | `agent-safari wait-for-text <text> --timeout <ms>` |
| `wait_for_idle(timeout_ms=10000)` | Wait for page load/fetch/XHR idle. | `agent-safari wait-for-idle --timeout <ms>` |
| `network_start()` | Start fetch/XHR network capture instrumentation. | `agent-safari network-start` |
| `network_list()` | Return captured fetch/XHR network entries. | `agent-safari network-list` |
| `network_stop()` | Stop fetch/XHR network capture instrumentation. | `agent-safari network-stop` |
| `network_export(path, body_preview_bytes=None, max_entries=None)` | Export redacted fetch/XHR entries to JSON. | `agent-safari network-export <path>` |
| `back()` | Navigate back in WebKit history if possible. | `agent-safari back` |
| `forward()` | Navigate forward in WebKit history if possible. | `agent-safari forward` |
| `reload()` | Reload the current page. | `agent-safari reload` |
| `viewport(width, height)` | Resize the WebKit viewport/window. | `agent-safari viewport <width> <height>` |
| `session()` | Return current automation session metadata. | `agent-safari session` |
| `tabs()` | List modeled tabs for the single-WebView session. | `agent-safari tabs` |
| `tab_new()` | Report/create the current tab placeholder. | `agent-safari tab-new` |
| `tab_switch(tab_id)` | Switch to a modeled tab id. | `agent-safari tab-switch <id>` |
| `tab_close(tab_id)` | Close a modeled tab id when supported. | `agent-safari tab-close <id>` |


### Example MCP control loop

From an MCP-capable agent, use the tools in this order:

```text
navigate(url="https://example.com")
snapshot()
click(selector="@e1", native=True)
fill(selector="@e2", value="hello@example.com")
type_text(text=" extra")
wait_for_idle(timeout_ms=10000)
screenshot_full(path="/tmp/agent-safari-full.png")  # CLI: screenshot --full --out <path>
evaluate(script="document.title")
```

For Hermes specifically, once the server is loaded, ask the agent to use the `agent-safari` MCP tools to navigate, snapshot, click/fill refs, and capture screenshots.

## Operational documentation

- CLI usage: `docs/CLI_USAGE.md`
- MCP wrapper usage: `docs/MCP_WRAPPER.md`
- CI/CD: `docs/CI_CD.md`
- Packaging and distribution: `docs/PACKAGING.md`
- Roadmap: `docs/ROADMAP.md`

## CI/CD

The repository has four GitHub Actions lanes:

- `CI`: runs on pushes and pull requests, covering Swift tests, release compilation, Python/shell syntax, npm package smoke, Homebrew formula rendering, audit tests, and public-release hygiene.
- `macOS Smoke`: manual and weekly real-daemon smoke lane for WKWebView automation, screenshots, DOM refs, network capture, and MCP wrapper bridging.
- `Release`: tag/manual CD lane that builds the release binary, packages a zip with checksums, packages npm, uploads workflow artifacts, and publishes a GitHub Release.
- `Publish Packages`: release-published lane that publishes npm when `NPM_TOKEN` exists and updates a Homebrew tap when `HOMEBREW_TAP_REPO`/`HOMEBREW_TAP_TOKEN` exist.

See `docs/CI_CD.md` and `docs/PACKAGING.md` for release commands and recommended branch protection settings.

## Smoke checks

The repository includes smoke scripts that exercise the operational path.

CLI smoke:

```sh
cd agent-safari
scripts/smoke_cli.sh
```

MCP wrapper smoke against an already running daemon:

```sh
cd agent-safari
AGENT_SAFARI_BIN="$PWD/.build/debug/agent-safari" \
AGENT_SAFARI_SOCKET=/tmp/agent-safari.sock \
python3 scripts/smoke_mcp_wrapper.py
```

`smoke_cli.sh` builds the Swift package, starts a daemon on a temporary socket, opens a generated local HTML page via the normalized `open` alias, exercises snapshot refs, fill, click, evaluate, normalized `network start/list/stop`, and `screenshot --full --out`, then cleans up.

`smoke_mcp_wrapper.py` imports `_run_cli` from `mcp/agent_safari_mcp.py`, validates the `--tools-json` MCP contract, and calls CLI-backed MCP wrapper operations against an already running daemon. It verifies `status` first, then exercises normalized `network start`, `network list`, and `network stop` around the existing open/evaluate/screenshot path. It uses `AGENT_SAFARI_BIN` and `AGENT_SAFARI_SOCKET` when set, and exits successfully with a skip message if no daemon is reachable.

Real-world GUI smoke:

```sh
cd agent-safari
python3 scripts/smoke_real_world.py
```

`smoke_real_world.py` runs five WebKit scenarios against generated local fixtures: snapshot refs/forms, full-page and element screenshots, fetch/XHR plus resource-timing network export, tab/session behavior, and native-click/type/viewport behavior. It prints `report=<artifact-dir>/REPORT.md` and `artifacts=<artifact-dir>` on success. The artifact directory contains `REPORT.md`, `data/scenario-results.json`, `captures/*.png`, and `daemon.log`.

Useful release-smoke options:

```sh
python3 scripts/smoke_real_world.py --out-dir .tmp/release-smoke
python3 scripts/smoke_real_world.py --socket /tmp/agent-safari-release-smoke.sock
python3 scripts/smoke_real_world.py --skip-build
AGENT_SAFARI_STRICT_NATIVE=1 python3 scripts/smoke_real_world.py
```

The full release gate is documented in `docs/RELEASE_CHECKLIST.md`.

## Useful environment variables

- `AGENT_SAFARI_BIN`: path to the built `agent-safari` binary for wrapper/smoke scripts.
- `AGENT_SAFARI_SOCKET`: Unix socket path for daemon and client commands.
- `AGENT_SAFARI_SMOKE_DIR`: optional directory for real-world smoke artifacts.
- `AGENT_SAFARI_STRICT_NATIVE`: set to `1` to make native-click fallback a hard failure in `scripts/smoke_real_world.py`.

## Current limitations

- The current daemon controls a modeled WKWebView tab set inside a single native WebKit window.
- Profile persistence/isolation is daemon-level; use `--profile` and `--ephemeral` deliberately.
- The MCP wrapper exposes wait commands, history commands, viewport, session, and tab commands, but it remains a thin CLI wrapper rather than a separate browser runtime.
- Passkey/WebAuthn automation is out of scope for the current roadmap.
- `key` dispatches synthetic DOM keyboard events; `type` is a DOM-level text insertion helper, not full native keyboard automation.
- Network capture is fetch/XHR instrumentation, not full proxy/CDP-style HAR capture.

## Notes

- Start only one daemon per socket path.
- Use a short socket path under `/tmp`; Unix socket paths have platform length limits.
- Full-page screenshots are written as PNG files at the path you provide.
- The WebKit daemon must run in a macOS GUI session; headless SSH-only sessions will not be sufficient.
