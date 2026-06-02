# Agentic browser QA example

This example shows a minimal observe → act → verify loop for a local web app.

## Start the daemon

```sh
agent-safari daemon --socket /tmp/agent-safari.sock
```

## Drive a page from the CLI

```sh
agent-safari open 'http://127.0.0.1:3000' --socket /tmp/agent-safari.sock
agent-safari wait-for-idle --timeout 10000 --socket /tmp/agent-safari.sock
agent-safari snapshot --socket /tmp/agent-safari.sock
agent-safari click '@e1' --native --socket /tmp/agent-safari.sock
agent-safari screenshot --full --out /tmp/agent-safari-qa.png --socket /tmp/agent-safari.sock
```

## Capture fetch/XHR activity

```sh
agent-safari network start --socket /tmp/agent-safari.sock
agent-safari click '@e2' --socket /tmp/agent-safari.sock
agent-safari wait-for-idle --timeout 10000 --socket /tmp/agent-safari.sock
agent-safari network list --socket /tmp/agent-safari.sock
agent-safari network export /tmp/agent-safari-network.json --body-preview-bytes 512 --socket /tmp/agent-safari.sock
agent-safari network stop --socket /tmp/agent-safari.sock
```

## Agent instruction template

```text
You are testing a rendered web app in Safari/WebKit.
First call observe/status, then snapshot. Use snapshot refs for click/fill actions. After each action, wait for idle and verify with text, screenshot, or evaluate. If a network request matters, start network capture before the action and export the captured fetch/XHR entries after verification.
```

## What this catches well

- Elements that render differently in WebKit than Chromium.
- Agent planning mistakes caused by missing visual context.
- Broken buttons/forms discoverable through snapshot refs.
- Fetch/XHR regressions visible through the network instrumentation.

## Known limits

- Network capture covers JavaScript `fetch` and `XMLHttpRequest`, not every browser resource request.
- The daemon requires a macOS GUI session.
- Native click verification may require Accessibility permission.
