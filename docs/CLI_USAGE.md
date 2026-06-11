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

Select profile metadata for persistent mode or an isolated non-persistent data store:

```sh
.build/debug/agent-safari daemon --profile qa --socket /tmp/agent-safari-qa.sock
.build/debug/agent-safari daemon --ephemeral --socket /tmp/agent-safari-ephemeral.sock
```

## Response format

Client commands print one JSON line. Success looks like:

```json
{"id":"...","ok":true,"result":{"key":"value"},"error":null}
```

Failures return `"ok": false` with an `error` object, or the CLI exits non-zero if it cannot connect to the daemon.
Click/fill actionability failures are raised from structured WebKit evaluation results; native input failures are raised from typed Swift errors. Both use stable `error.code` values:

- `actionability_stale_ref`
- `actionability_refs_unavailable`
- `actionability_missing_selector`
- `actionability_disabled`
- `actionability_hidden`
- `actionability_off_viewport`
- `actionability_occluded`
- `native_click_unverified`
- `native_input_failed`
- `wait_timeout` — `wait-for-selector`, `wait-for-text`, or `wait-for-idle` exceeded the timeout
- `invalid_url` — the provided URL could not be parsed
- `missing_param` — a required parameter was not supplied
- `invalid_param` — a parameter value is not a valid integer
- `unknown_method` — the requested command is not recognised
- `element_resolution_failed` — the target element could not be resolved to a clickable point
- `screenshot_failed` — screenshot PNG encoding failed
- `page_measurement_failed` — page dimension measurement failed
- `javascript_encoding_failed` — JavaScript string literal encoding failed
- `socket_error` — Unix socket path is too long or a socket operation failed
- `unknown_tab` — the referenced tab id does not exist
- `navigation_in_progress` — a navigation is already in flight on the target tab
- `tab_closed_during_command` — the target tab was closed while the command was running
- `tab_not_active_for_native_input` — native Quartz input requires the visible tab
- `upload_file_not_found` — an `upload` path does not exist on disk
- `upload_panel_not_triggered` — the upload click never opened a file panel for the input
- `upload_multiple_not_allowed` — multiple paths were given for an input without the `multiple` attribute

## Commands

All client commands accept `--socket <path>`.

### Navigate

Prefer the normalized `open` command. `navigate` remains as a backward-compatible alias.

```sh
.build/debug/agent-safari open 'https://example.com' --socket /tmp/agent-safari.sock
.build/debug/agent-safari navigate 'https://example.com' --socket /tmp/agent-safari.sock
```

Result fields include the final `url` and document `title` when available.

Fragment-only navigations (the target differs from the current URL only by a `#fragment`) are handled as same-document navigations: they update the location via JavaScript instead of a full page load and return immediately with an extra `sameDocument: true` result field. Cross-document navigations omit `sameDocument` and use the normal load path.

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

The result contains `result.elements`, an array with visible interactive elements. Each element may include:

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

Native click fallback is explicit in the JSON result. Verified native clicks report `method: "native"`, `nativeVerified: true`, and `fallbackUsed: false`. If default native click cannot be verified and DOM fallback succeeds, the result reports `method: "dom-fallback"`, `nativeVerified: false`, `fallbackUsed: true`, `nativeError`, and `nativeErrorCode`. Use `--no-fallback` when native-only verification matters. When a click triggers a `target=_blank` link or `window.open()`, the navigation is redirected to the current active WebView and the result includes `popupRedirectedURL` with the intercepted URL. A bare `window.open()` with no URL is ignored and reports nothing.

### Upload files to a file input

Drive an `<input type="file">` element by setting its files through the WebKit
open panel. The selector may be a CSS selector or a snapshot `@e` ref:

```sh
.build/debug/agent-safari upload '#avatar' /path/to/photo.png --socket /tmp/agent-safari.sock
.build/debug/agent-safari upload '@e4' /path/to/a.txt /path/to/b.txt --socket /tmp/agent-safari.sock
```

The command validates every path exists, arms the pending files for the target
tab, clicks the input to open the WebKit file panel, and then verifies the input
actually received the files. Result fields:

- `selector`: the resolved selector or ref.
- `fileCount`: the number of files now on the input (`element.files.length`).
- `files`: a JSON array string of the selected file basenames.
- `changeEventSynthesized`: `"true"` if agent-safari dispatched `input`/`change`
  because WebKit did not fire `change` natively, `"false"` if WebKit fired it.

Rules and failures:

- Multiple paths are only allowed when the input has the `multiple` attribute;
  otherwise the command fails with `upload_multiple_not_allowed`.
- A missing path fails with `upload_file_not_found` and names the missing path.
- If the click never opens a file panel, the pending files are disarmed and the
  command fails with `upload_panel_not_triggered`. This also happens when the
  selector is not a file input.

Like native Quartz input, the WebKit file open panel is presented by macOS only
in a real GUI session. Validation (`upload_file_not_found`,
`upload_multiple_not_allowed`) and arming are environment-independent, but the
panel that actually sets the files requires a logged-in GUI session (the same
gate as `click --native`); a headless daemon returns `upload_panel_not_triggered`.

Each `--tab <id>` upload arms files only for that modeled tab; a click on the
visible tab cannot consume another tab's pending upload files.

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
.build/debug/agent-safari screenshot --out /tmp/agent-safari-viewport.png --socket /tmp/agent-safari.sock
```

Full-page screenshot:

```sh
.build/debug/agent-safari screenshot --full --out /tmp/agent-safari-full.png --socket /tmp/agent-safari.sock
```

`result.path` contains the written PNG path. `result.strategy` describes whether a single full-page capture or fallback strategy was used.

Element screenshot using a CSS selector or latest snapshot ref:

```sh
.build/debug/agent-safari snapshot --socket /tmp/agent-safari.sock
.build/debug/agent-safari screenshot-element '@e2' --out /tmp/button.png --socket /tmp/agent-safari.sock
.build/debug/agent-safari screenshot --element '#submit' --out /tmp/submit.png --socket /tmp/agent-safari.sock
```

### Session, tabs, and profile state

The daemon exposes a modeled tab set inside one native WebKit window. Each modeled tab has a `WKWebView`; one active tab is attached to the window at a time.

```sh
.build/debug/agent-safari session --socket /tmp/agent-safari.sock
.build/debug/agent-safari tabs --socket /tmp/agent-safari.sock
.build/debug/agent-safari tab-new 'https://example.com' --socket /tmp/agent-safari.sock
.build/debug/agent-safari tab-switch tab-1 --socket /tmp/agent-safari.sock
.build/debug/agent-safari tab-close tab-2 --socket /tmp/agent-safari.sock
```

`session` reports `sessionId`, `activeTabId`, `profile`, `persistent`, `dataStore`, and `tabCount`. `--profile <name>` is metadata reserved for future named stores; today persistent mode uses WebKit's default data store, and `--ephemeral` uses a non-persistent store. Use separate daemon sockets plus `--ephemeral` for isolated automation runs.

### Parallel multi-tab targeting

Any page command accepts a global `--tab <id>` option that routes it to a modeled tab without changing the active tab. Commands addressed to different tabs run concurrently: a long `wait-for-*` on one tab does not delay commands on another, and parallel `navigate` calls land on their own tabs. Every result reports the `tabId` it acted on.

```sh
.build/debug/agent-safari navigate 'https://example.com' --tab tab-2 --socket /tmp/agent-safari.sock
.build/debug/agent-safari wait-for-selector '#result' --timeout 30000 --tab tab-2 --socket /tmp/agent-safari.sock &
.build/debug/agent-safari click '#submit' --tab tab-1 --socket /tmp/agent-safari.sock
```

Limits, by design:

- Tabs share one window, one viewport, and one cookie/data store (log in once, drive N tabs). For isolation, run separate daemons on separate sockets.
- An unknown tab id fails with `error.code: "unknown_tab"` before any action runs; if the tab is closed mid-command the result is `tab_closed_during_command`.
- A second `navigate` on a tab whose navigation is still in flight fails with `navigation_in_progress`.
- Native (Quartz) input requires the visible tab; `click --native --tab <background>` fails with `tab_not_active_for_native_input`. DOM click/fill/evaluate work on background tabs.
- Background tabs render off-window: screenshots and DOM reads work, but rendering may be throttled by WebKit for long-idle background tabs.

## Local file navigation

Generate an absolute `file://` URL and pass it to `open`:

```sh
HTML=/tmp/agent-safari-smoke.html
printf '<!doctype html><title>Smoke</title><button>OK</button>' > "$HTML"
URL="file://$HTML"
.build/debug/agent-safari open "$URL" --socket /tmp/agent-safari.sock
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

The smoke script builds, starts a temporary daemon, opens local HTML via `open`, uses snapshot refs for fill/click, exercises normalized `network start/list/stop`, captures a full-page screenshot through `screenshot --full --out`, verifies modeled tabs, captures an element screenshot, exports HAR-like network JSON, and reports artifact paths.

## Network command handling

Network capture commands are available as normalized `network <subcommand>` commands. Legacy `network-start`, `network-list`, and `network-stop` aliases remain available. Capture uses JavaScript fetch/XHR instrumentation and therefore does not provide full browser/proxy HAR coverage.

```sh
.build/debug/agent-safari network start --socket /tmp/agent-safari.sock
.build/debug/agent-safari network list --socket /tmp/agent-safari.sock
.build/debug/agent-safari network stop --socket /tmp/agent-safari.sock
.build/debug/agent-safari network export /tmp/network.json --max-entries 25 --socket /tmp/agent-safari.sock
```

The exported JSON is HAR-like: `log.version`, `log.creator`, `log.entries`, and `agentSafari` metadata. It remains fetch/XHR-only JavaScript instrumentation.

## Agent loop and persistence docs

- `docs/AGENT_LOOP.md` documents the recommended observe -> act -> wait -> verify loop.
- `docs/PROFILE_PERSISTENCE.md` documents profile/session persistence behavior and roadmap.

## Troubleshooting

- `connect failed`: the daemon is not running, the socket path is wrong, or the daemon failed to bind.
- Socket path too long: use a shorter path under `/tmp`.
- No WebKit window appears: run from an interactive macOS GUI session.
- Screenshot path errors: ensure the parent directory exists or is creatable by your user.
