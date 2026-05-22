# Network Capture Spike

## Scope and current baseline

This spike designs a WebKit-compatible network capture path for the Agent Safari daemon without changing `Sources/AgentSafari/main.swift` production code.

Current daemon facts from inspection:

- `BrowserController` owns a single `WKWebView` and exposes `navigate`, `evaluate`, `text`, `html`, `screenshot`, `click`, `fill`, and `key` over the local RPC handler.
- `evaluateJavaScript` is already available and can inject ad-hoc scripts into the current document.
- `WKNavigationDelegate` is already installed and currently only resolves navigation completion/failure.
- The current CLI parser has no network commands yet; existing commands map directly to RPC methods.
- `IMPLEMENTATION_PLAN.md` already correctly calls network observability a phased WebKit design rather than CDP parity.

Non-goals for this spike:

- Do not promise CDP-equivalent interception from `WKWebView` alone.
- Do not edit `Sources/AgentSafari/main.swift` in this spike.
- Do not touch DOM snapshot or full-page screenshot docs.

## Phase 1: injected JS fetch/XMLHttpRequest logging MVP

Use a page script that monkey-patches `window.fetch` and `window.XMLHttpRequest` and stores entries in `window.__agentSafariNetworkLog`.

Standalone spike snippet:

- `docs/spikes/network_capture_instrumentation.js`

Recommended production shape after this spike:

1. Add a Swift helper, e.g. `AutomationRuntime.networkCaptureScript`, containing the minified or loaded JS string.
2. Install it as a `WKUserScript` with injection time `.atDocumentStart`.
3. Choose frame scope deliberately: `forMainFrameOnly: false` for iframe coverage, or `true` for simpler output.
4. Keep `evaluateJavaScript` fallback for the already-loaded current document:
   - `network start` can inject the script immediately into the active page.
   - future navigations should get the `WKUserScript` automatically.
5. Add methods that evaluate:
   - `window.__agentSafariNetwork.clear()` for start/reset.
   - `window.__agentSafariNetwork.list()` for list/stop.
   - `window.__agentSafariNetwork.export()` for JSON export.

MVP captured fields:

- request type: `fetch` or `xhr`
- request method and URL
- request headers available to JavaScript
- bounded request body preview where practical
- response URL, status, status text, ok flag
- response headers exposed to JavaScript
- start/end timing and duration
- error string for rejected fetches or failed XHRs

MVP limitations:

- Cannot see parser-driven loads: document HTML, images, scripts, stylesheets, fonts, favicons, media.
- Cannot see WebSocket frames or EventSource messages.
- Cannot see requests initiated before the script is installed unless installed at document start before navigation.
- Cannot reliably capture cross-origin response bodies; CORS still applies.
- Cannot observe service worker internal traffic completely.
- Monkey-patching may be bypassed by code that captured native `fetch`/`XMLHttpRequest` before injection.
- Response body capture is intentionally not included in the MVP because consuming/cloning response streams changes memory and timing behavior; add as opt-in previews only.

Data model suggestion:

```json
{
  "id": 1,
  "type": "fetch",
  "phase": "response",
  "method": "POST",
  "url": "https://api.example.test/items",
  "requestHeaders": {"content-type": "application/json"},
  "requestBodyPreview": "{...}",
  "status": 201,
  "statusText": "Created",
  "ok": true,
  "responseURL": "https://api.example.test/items",
  "responseHeaders": {"content-type": "application/json"},
  "startedAt": 123.45,
  "endedAt": 150.12,
  "durationMs": 26.67,
  "wallTime": "2026-05-21T00:00:00.000Z"
}
```

## Phase 2: navigation delegate logging and limits

`WKNavigationDelegate` is useful for top-level navigation state, but it is not a general network tap.

What it can provide:

- top-level navigation start/commit/finish/failure lifecycle
- provisional navigation errors
- redirect policy decisions when using `decidePolicyFor navigationAction`
- main-frame URL, navigation type, target frame information
- coarse success/failure for document navigation

What it cannot provide as a CDP replacement:

- all subresource requests
- arbitrary HTTPS request/response headers
- response bodies
- precise transfer sizes, timing phases, cache/source details
- request interception/rewrite for normal `http`/`https` subresources
- HAR completeness

Recommended usage:

- Add a native `NavigationEvent` log beside the JS network log.
- Keep it separate from fetch/XHR entries but export both in one envelope.
- Use it to explain page loads and redirects, not to claim full network capture.

Example event shape:

```json
{
  "type": "navigation",
  "phase": "didFinish",
  "url": "https://example.com/",
  "isMainFrame": true,
  "wallTime": "2026-05-21T00:00:00.000Z"
}
```

`WKURLSchemeHandler` note:

- Good for custom app-owned schemes.
- Not a universal hook for arbitrary `https://` traffic in a normal `WKWebView`.
- Avoid presenting it as the main network capture path unless the app rewrites URLs to custom schemes, which is invasive and likely to break real sites.

## Phase 3: local proxy path for HAR and response bodies

For complete request/response capture, including response bodies, use an explicit local proxy mode.

Recommended design:

1. Agent Safari starts or attaches to a local HTTP(S) proxy process.
2. The daemon creates a dedicated `WKWebsiteDataStore`/session profile for proxy capture.
3. The user explicitly opts into system or per-process proxy configuration.
4. For HTTPS body capture, the user explicitly trusts a local root certificate or uses a generated per-session CA.
5. The proxy writes HAR-like artifacts with request/response headers, timings, body previews, and optional full bodies.
6. The CLI reports whether capture is JS-only, navigation-only, or proxy-backed.

Important WebKit/macOS caveat:

- `WKWebView` does not expose a simple per-instance proxy property for arbitrary HTTP/S traffic. Proxy configuration may require system network settings, a custom `URLSession` only for app-originated requests, or a helper/proxy setup that the user explicitly enables. This must be documented as opt-in because it affects trust and privacy.

Proxy advantages:

- Captures document and subresource requests.
- Can produce HAR with timings and bodies.
- Can support response body export and later controlled rewrite/abort behavior.
- Works independently of page JavaScript monkey patches.

Proxy risks and mitigations:

- TLS interception requires trust setup: require an explicit command, warning, and teardown path.
- Sensitive data capture: default to metadata/body previews; require `--include-bodies` for full bodies.
- System proxy side effects: prefer isolated profile and clear status indicators; document cleanup commands.
- HTTP/2, HTTP/3, WebSocket, compression, and streaming need explicit proxy support and tests.

## Proposed CLI commands

Prefer a small `network` namespace that can grow from JS-only to proxy-backed capture:

```bash
agent-safari network start [--mode js|proxy] [--clear] [--include-bodies] [--output DIR]
agent-safari network stop [--export PATH]
agent-safari network list [--json]
agent-safari network export --output network.json [--format json|har]
```

RPC methods:

```text
network.start
network.stop
network.list
network.export
```

Simple MVP alternative if command surface should stay tiny:

```bash
agent-safari network-log start
agent-safari network-log list
agent-safari network-log export /tmp/network.json
agent-safari network-log stop
```

Recommended command semantics:

- `network start --mode js --clear`
  - injects/installs fetch/XHR instrumentation and clears the page log.
  - returns mode, active URL, and whether document-start injection is active for future navigations.
- `network list --json`
  - returns current JS log plus native navigation events.
- `network stop --export PATH`
  - returns final log and optionally writes it to disk.
  - for JS mode, stop can mean “disable collection for future navigations and read final entries”; it cannot safely unpatch existing page functions without reload.
- `network export --format har`
  - for JS mode, produce a best-effort HAR-like JSON and mark it as partial.
  - for proxy mode, produce real HAR when proxy data is available.

Result envelope suggestion:

```json
{
  "mode": "js",
  "complete": false,
  "entries": [],
  "navigationEvents": [],
  "warnings": ["JS mode does not capture subresources or response bodies"]
}
```

## Tests and smoke plan

No production code was changed in this spike, so the immediate verification is documentation/script validation. Future implementation should use the following tests.

### Unit tests

- CLI parser maps `network start`, `network stop`, `network list`, and `network export` to RPC methods.
- Unknown network subcommands return deterministic errors.
- JS log envelope encoding preserves entries and warnings.
- HAR exporter marks JS-only output as partial and proxy output as complete.

### JavaScript instrumentation tests

Run the snippet in a JS environment with mocked `fetch` and `XMLHttpRequest`:

- installing twice is idempotent.
- successful fetch creates one entry with method, URL, status, headers, and duration.
- rejected fetch marks `phase: "error"` and rethrows.
- XHR `open`/`send`/`loadend` records method, URL, status, headers, and body preview.
- `clear`, `list`, and `export` work.
- log is bounded to avoid unbounded page memory growth.

### WebKit smoke tests

Use a local HTTP server fixture with endpoints:

- `/` serves an HTML page that calls fetch and XHR after load.
- `/api/fetch` returns JSON.
- `/api/xhr` returns text.
- `/img.png` verifies JS-only mode does not claim subresource capture.
- `/redirect` verifies navigation delegate redirect/top-level behavior.
- `/cors` verifies exposed response headers obey CORS.

Manual smoke sequence after implementation:

```bash
swift build
.build/debug/agent-safari daemon --socket /tmp/agent-safari.sock
agent-safari --socket /tmp/agent-safari.sock navigate http://127.0.0.1:PORT/
agent-safari --socket /tmp/agent-safari.sock network start --mode js --clear
agent-safari --socket /tmp/agent-safari.sock evaluate "fetch('/api/fetch').then(() => true)"
agent-safari --socket /tmp/agent-safari.sock evaluate "var x=new XMLHttpRequest();x.open('POST','/api/xhr');x.send('hello')"
agent-safari --socket /tmp/agent-safari.sock network list --json
agent-safari --socket /tmp/agent-safari.sock network export --output /tmp/agent-safari-network.json
```

Expected smoke result:

- Fetch and XHR entries appear with method/url/status/duration.
- Image/script/css subresources are absent or clearly marked as unsupported in JS mode.
- Export contains warnings that JS mode is partial.
- Existing `navigate`, `text`, `html`, `screenshot`, `click`, `fill`, and `key` behavior remains unchanged.

### Proxy smoke tests

After proxy mode exists:

- Start a local proxy with a temporary CA.
- Confirm explicit trust/setup prompt is required before HTTPS body capture.
- Navigate a fixture page with document, JS, CSS, image, fetch, and XHR requests.
- Export HAR and validate it contains document and subresource entries.
- Validate response body capture only when `--include-bodies` is passed.
- Stop proxy and verify system/proxy settings are cleaned up.

## Phased implementation path

1. Documentation-only spike: this file plus standalone JS snippet. No production Swift edits.
2. Add `NetworkCaptureRuntime` or `AutomationRuntime` helper that owns the injected JS string.
3. Add `NetworkCaptureStore` model for JS entries and native navigation events.
4. Add RPC methods `network.start`, `network.stop`, `network.list`, `network.export`.
5. Add CLI parser support for `network start/stop/list/export` or the smaller `network-log` alias.
6. Install `WKUserScript` at document start on `network start`; inject immediately with `evaluateJavaScript` for the current page.
7. Add native navigation delegate event recording while preserving existing navigation continuations.
8. Add JSON export, then best-effort HAR export with an explicit `partial: true` marker for JS mode.
9. Add proxy-backed capture as an opt-in advanced mode for complete HAR and response bodies.

## Findings

- WebKit can support useful agentic request observability quickly through injected fetch/XHR logging.
- `WKNavigationDelegate` should be treated as navigation lifecycle metadata, not as a full network event source.
- Complete HAR and response body capture needs a proxy path; this should be explicit and opt-in due to TLS trust and system proxy side effects.
- The cleanest CLI shape is `network start/stop/list/export`; `network-log` is acceptable for a narrower MVP but may need migration later.
