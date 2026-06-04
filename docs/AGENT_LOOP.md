# Agent loop recipe

This document defines the recommended `observe -> act -> wait -> verify` loop for agents that drive agent-safari through the CLI or MCP wrapper.

## Loop

1. Open or switch to the target modeled tab.

```sh
agent-safari open 'https://example.com'
# or
agent-safari tab-new 'https://example.com'
agent-safari tab-switch tab-2
```

Modeled tabs are scoped to the current daemon/socket. Use separate daemons and sockets for independent browser sessions.

2. Observe stable page state.

```sh
agent-safari observe
agent-safari snapshot
```

Use `observe` for page-level state and `snapshot` for actionable element refs. Snapshot elements include `ref`, `role`, `accessibleName`, `text`, `selector`, `bounds`, `center`, `disabled`, `editable`, `viewportIntersecting`, and occlusion metadata.

3. Act with a snapshot ref when possible.

```sh
agent-safari fill '@e1' 'value'
agent-safari click '@e2' --native
```

Prefer refs from the latest snapshot. Re-run `snapshot` after navigation or large DOM changes.

4. Wait for the expected condition.

```sh
agent-safari wait-for-idle --timeout 10000
agent-safari wait-for-selector '#result' --timeout 10000
agent-safari wait-for-text 'Saved' --timeout 10000
```

5. Verify with text, evaluate, screenshot, and/or network capture.

```sh
agent-safari text
agent-safari evaluate 'document.title'
agent-safari screenshot --full --out /tmp/page.png
agent-safari screenshot-element '@e2' --out /tmp/button.png
agent-safari network list
```

## Network verification

For flows where API behavior matters:

```sh
agent-safari network start
agent-safari click '@e3' --native
agent-safari wait-for-idle --timeout 10000
agent-safari network list
agent-safari network export /tmp/network.har.json --max-entries 50 --body-preview-bytes 1024
agent-safari network stop
```

The export is HAR-like JSON with `log.version`, `log.creator`, `log.entries`, and `agentSafari` metadata. It is intentionally marked as fetch/XHR JavaScript instrumentation, not proxy-grade full browser capture.


## Release smoke loop

Before relying on a release candidate, run the GUI smoke from a logged-in macOS session:

```sh
python3 scripts/smoke_real_world.py
```

The smoke runner exercises the recommended loop across five local scenarios and writes a human-readable report plus machine-readable data:

- `REPORT.md` for summary, native-click delivery metadata, and embedded screenshots
- `data/scenario-results.json` for structured results, including screenshot byte size and dimensions
- `captures/*.png` for viewport, full-page, and element evidence; the runner asserts files are non-empty PNGs and that the long full-page capture is taller than the viewport capture
- `daemon.log` for daemon diagnostics

Useful controls:

```sh
python3 scripts/smoke_real_world.py --out-dir .tmp/release-smoke
python3 scripts/smoke_real_world.py --socket /tmp/agent-safari-release-smoke.sock
python3 scripts/smoke_real_world.py --skip-build
AGENT_SAFARI_STRICT_NATIVE=1 python3 scripts/smoke_real_world.py
```

See `docs/RELEASE_CHECKLIST.md` for the full non-GUI and GUI release gate.

## Failure policy

- If a ref action fails, run `snapshot` again before retrying.
- If native click is not observed, the default fallback uses JavaScript click and the click result records `method: "dom-fallback"`, `nativeVerified: false`, `fallbackUsed: true`, and `nativeError`. Use `--no-fallback` when native-only verification matters.
- If waiting times out, capture `observe`, `snapshot`, `text`, and a screenshot before deciding the next action.
