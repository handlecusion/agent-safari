# Profile, cookies, and session persistence

agent-safari now exposes the first persistence contract for daemon sessions.

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
- The daemon does not yet expose cookie import/export commands.

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

## Roadmap

The profile flag intentionally lands before full cookie APIs so external agents can depend on a stable command shape. The next persistence milestones are:

1. Cookie export/import tools using `WKHTTPCookieStore`.
2. Named profile registry under `~/.agent-safari/profiles/<name>/metadata.json`.
3. Explicit clear-profile command for destructive test isolation.
4. Session snapshot artifact that records active tab id, URLs, viewport, and capture settings.

Until those land, use separate daemon sockets plus `--ephemeral` for isolated automation runs.
