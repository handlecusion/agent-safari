# Session, tabs, profiles, and persistence

This is the Phase 5 design note for the current `agent-safari` session/tab/profile contract.

The current contract is intentionally smaller than true browser isolation. It documents the shipped single-daemon model so CLI, MCP, smoke tests, and public docs describe the same behavior.

## Definitions

- **Session**: one running daemon process reachable through one Unix socket. A session has one `sessionId`, one native WebKit window, one active tab id, and one selected persistence mode.
- **Tab**: one modeled in-process browser target backed by a `WKWebView`. The daemon can keep multiple modeled tabs, but only the active tab's `WKWebView` is attached to the native window at a time.
- **Window**: one native AppKit window owned by the daemon. `agent-safari` does not claim true multi-window support and is not a true browser multi-target implementation.
- **Profile**: startup metadata plus the selected WebKit data store mode. `--profile <name>` is reported in session metadata and reserved for future named profile stores; it does not create a separate named cookie/cache directory today.
- **Artifact scope**: caller-owned output paths. Smoke runs create per-run directories; the daemon does not assign per-tab or per-profile artifact namespaces.
- **MCP session scope**: socket-scoped. The MCP wrapper delegates to the CLI and targets one daemon via `AGENT_SAFARI_SOCKET`. Multiple independent sessions require multiple daemon processes with separate sockets.

## Daemon profile flags

```sh
agent-safari daemon --profile default --socket /tmp/agent-safari.sock
agent-safari daemon --profile qa --socket /tmp/agent-safari-qa.sock
agent-safari daemon --ephemeral --socket /tmp/agent-safari-ephemeral.sock
```

Current behavior:

- Persistent mode uses WebKit's default `WKWebsiteDataStore.default()`.
- Ephemeral mode uses `WKWebsiteDataStore.nonPersistent()`.
- `--profile <name>` is reported in `session()` metadata and reserved as the stable CLI contract for future per-profile stores.
- All modeled tabs in a daemon share the daemon's selected persistence mode.
- Cookie export/import is available via `cookies export <path>` and `cookies import <path>`. See `docs/CLI_USAGE.md` for details.

Check effective session state:

```sh
agent-safari session
```

Expected fields include:

- `sessionId`
- `activeTabId`
- `profile`
- `persistent`
- `dataStore`
- `tabCount`

## Tab/session model

The daemon keeps an in-process tab model over native `WKWebView` instances:

```sh
agent-safari tabs
agent-safari tab-new 'https://example.com'
agent-safari tab-switch tab-2
agent-safari tab-close tab-2
```

Each tab has its own `WKWebView` while sharing the daemon's selected persistence mode. Closing the last tab is refused so the daemon always has an active browser target.

Expected tab result fields:

- `tabs`: array of modeled tabs with `id`, `active`, `url`, `title`, and `loading`.
- `activeTabId`: active modeled tab id.

Expected lifecycle result fields:

- `tab-new`: `id`, `tabId`, `created`, `url`, `title`.
- `tab-switch`: `id`, `tabId`, `active`, `url`, `title`.
- `tab-close`: `id`, `tabId`, `closed`, `activeTabId`, `reason`; successful closes return an empty `reason`, while closing the last tab returns `closed: "false"` and `reason: "cannot-close-last-tab"`.

## Isolation boundaries

Use these boundaries when designing tests or MCP clients:

- For isolated automation runs, start a separate daemon with a unique socket and `--ephemeral`.
- For long-lived local browsing state, use persistent mode knowingly; it uses WebKit's default data store today.
- For concurrent independent browser sessions, use separate daemon processes and separate sockets.
- Do not assume named `--profile` values isolate cookies/cache/storage until named profile stores are implemented.
- Do not assume screenshots or network exports are isolated by tab/profile unless the caller passes isolated output paths.

## Roadmap

The current Phase 5 contract is closed at the modeled daemon/session/tab/profile layer. Future persistence milestones are:

1. Cookie export/import tools using `WKHTTPCookieStore`. (Implemented 2026-06-11 — see `docs/CLI_USAGE.md` and `BrowserControllerCookies.swift`.)
2. Named profile registry under `~/.agent-safari/profiles/<name>/metadata.json`.
3. Explicit clear-profile command for destructive test isolation.
4. Session snapshot artifact that records active tab id, URLs, viewport, and capture settings.

Until those land, use separate daemon sockets plus `--ephemeral` for isolated automation runs.
