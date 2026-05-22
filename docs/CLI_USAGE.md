# agent-safari CLI usage

This guide documents the practical local operations for building, starting, and driving `agent-safari` from a terminal.

## Prerequisites

- macOS 14 or newer.
- Swift Package Manager available as `swift`.
- A logged-in GUI session. The daemon creates a native WebKit window and is not a headless browser.

## Build

From the repository root:

```sh
swift build
```

The debug binary is written to:

```sh
.build/debug/agent-safari
```

## Start the daemon

```sh
.build/debug/agent-safari daemon --socket /tmp/agent-safari.sock
```

The daemon shows the WebKit window without stealing keyboard focus by default. Use `--focus-window` when you explicitly want the window to become focused on launch:

```sh
.build/debug/agent-safari daemon --focus-window --socket /tmp/agent-safari.sock
```

The daemon listens on the Unix socket and keeps running until interrupted. Use a unique socket path when running multiple test sessions:

```sh
SOCKET="/tmp/agent-safari.$$.sock"
.build/debug/agent-safari daemon --socket "$SOCKET"
```

## Response format

Client commands print one JSON line. Success looks like:

```json
{"id":"...","ok":true,"result":{"key":"value"},"error":null}
```

Failures return `"ok": false` with an `error` object, or the CLI exits non-zero if it cannot connect to the daemon.

## Commands

All client commands accept `--socket <path>`.

### Navigate

```sh
.build/debug/agent-safari navigate 'https://example.com' --socket /tmp/agent-safari.sock
```

Result fields include the final `url` and document `title` when available.

### Read page text or HTML

```sh
.build/debug/agent-safari text --socket /tmp/agent-safari.sock
.build/debug/agent-safari html --socket /tmp/agent-safari.sock
```

### Evaluate JavaScript

```sh
.build/debug/agent-safari evaluate 'document.title' --socket /tmp/agent-safari.sock
```

The result is returned as `result.value`.

### Snapshot interactive elements

```sh
.build/debug/agent-safari snapshot --socket /tmp/agent-safari.sock
```

The result contains `result.snapshot`, a JSON string with visible interactive elements. Each element may include:

- `ref`: stable in-page reference such as `@e1`.
- `tag`, `text`, `selector`, `role`, `type`, `name`.
- `bounds`: viewport coordinates.

Run `snapshot` before using `@e...` refs. Re-run it after navigation or significant DOM changes.

### Fill, click, type, and key events

Selectors can be CSS selectors or snapshot refs:

```sh
.build/debug/agent-safari fill '#search' 'agent safari' --socket /tmp/agent-safari.sock
.build/debug/agent-safari click 'button[type="submit"]' --socket /tmp/agent-safari.sock
.build/debug/agent-safari click 'button[type="submit"]' --native --socket /tmp/agent-safari.sock
```

Using refs from `snapshot`:

```sh
INPUT_REF='@e1'
BUTTON_REF='@e2'
.build/debug/agent-safari fill "$INPUT_REF" 'hello' --socket /tmp/agent-safari.sock
.build/debug/agent-safari click "$BUTTON_REF" --native --socket /tmp/agent-safari.sock
.build/debug/agent-safari type ' world' --socket /tmp/agent-safari.sock
```

Keyboard events are dispatched to the active element. `type` inserts text into the active input, textarea, or contenteditable element and falls back to synthetic key events for other targets:

```sh
.build/debug/agent-safari key Enter --socket /tmp/agent-safari.sock
.build/debug/agent-safari type 'hello' --socket /tmp/agent-safari.sock
```

### Wait and observe page state

Use wait commands to make agentic browser control less race-prone after navigation or actions that mutate the DOM:

```sh
.build/debug/agent-safari wait 500 --socket /tmp/agent-safari.sock
.build/debug/agent-safari wait-for-selector '#results' --timeout 10000 --socket /tmp/agent-safari.sock
.build/debug/agent-safari wait-for-text 'Loaded' --timeout 10000 --socket /tmp/agent-safari.sock
.build/debug/agent-safari wait-for-idle --timeout 10000 --socket /tmp/agent-safari.sock
```

`wait-for-selector`, `wait-for-text`, and `wait-for-idle` poll until the condition is true or the timeout expires. The default timeout is 10 seconds. `wait-for-idle` requires `document.readyState == "complete"`, no active WebKit load, and no pending fetch/XHR requests observed by the optional network instrumentation.

### Screenshots

Viewport screenshot:

```sh
.build/debug/agent-safari screenshot /tmp/agent-safari-viewport.png --socket /tmp/agent-safari.sock
```

Full-page screenshot:

```sh
.build/debug/agent-safari screenshot-full /tmp/agent-safari-full.png --socket /tmp/agent-safari.sock
```

`result.path` contains the written PNG path. `result.strategy` describes whether a single full-page capture or fallback strategy was used.

## Local file navigation

Generate an absolute `file://` URL and pass it to `navigate`:

```sh
HTML=/tmp/agent-safari-smoke.html
printf '<!doctype html><title>Smoke</title><button>OK</button>' > "$HTML"
URL="file://$HTML"
.build/debug/agent-safari navigate "$URL" --socket /tmp/agent-safari.sock
```

## Smoke script

Run the end-to-end CLI smoke:

```sh
scripts/smoke_cli.sh
```

Useful overrides:

```sh
AGENT_SAFARI_SOCKET=/tmp/my-agent-safari.sock scripts/smoke_cli.sh
AGENT_SAFARI_SMOKE_DIR=/tmp/my-agent-safari-artifacts scripts/smoke_cli.sh
```

The smoke script builds, starts a temporary daemon, navigates to local HTML, uses snapshot refs for fill/click, exercises network capture when available, captures a full-page screenshot, and reports artifact paths.

## Network command handling

Network capture commands are available as `network-start`, `network-list`, and `network-stop`. They use JavaScript fetch/XHR instrumentation and therefore do not provide full browser/proxy HAR coverage.

```sh
.build/debug/agent-safari network-start --socket /tmp/agent-safari.sock
.build/debug/agent-safari network-list --socket /tmp/agent-safari.sock
.build/debug/agent-safari network-stop --socket /tmp/agent-safari.sock
```

## Troubleshooting

- `connect failed`: the daemon is not running, the socket path is wrong, or the daemon failed to bind.
- Socket path too long: use a shorter path under `/tmp`.
- No WebKit window appears: run from an interactive macOS GUI session.
- Screenshot path errors: ensure the parent directory exists or is creatable by your user.
