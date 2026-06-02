# Claude Desktop MCP setup

Use this example when you want Claude Desktop to control a local Agent Safari daemon.

## 1. Install Agent Safari

```sh
brew tap handlecusion/agent-safari
brew install agent-safari
```

Or build from source:

```sh
git clone https://github.com/handlecusion/agent-safari.git
cd agent-safari
scripts/install_cli.sh
```

## 2. Start the WebKit daemon

```sh
agent-safari daemon --socket /tmp/agent-safari.sock
```

The daemon owns a visible native WebKit window, so it must run in a logged-in macOS GUI session.

## 3. Register the MCP server

Recommended consent-first helper:

```sh
agent-safari-mcp-setup --dry-run
agent-safari-mcp-setup
```

Manual Claude Desktop config shape:

```json
{
  "mcpServers": {
    "agent-safari": {
      "command": "python3",
      "args": ["/opt/homebrew/share/agent-safari/mcp/agent_safari_mcp.py"],
      "env": {
        "AGENT_SAFARI_BIN": "/opt/homebrew/bin/agent-safari",
        "AGENT_SAFARI_SOCKET": "/tmp/agent-safari.sock"
      }
    }
  }
}
```

Adjust the paths if you installed into a different Homebrew prefix or built from source.

## 4. Try a browser task

Ask Claude:

```text
Use Agent Safari to open https://example.com, take a snapshot, click the first link if present, then capture a screenshot.
```

Useful tools exposed by the MCP wrapper include `navigate`, `snapshot`, `click`, `fill`, `screenshot`, `screenshot_full`, `evaluate`, `network_start`, `network_list`, `network_stop`, `tab_new`, `tab_switch`, and `wait_for_idle`.

## Troubleshooting

- If tools fail with a socket error, make sure the daemon is running with the same `AGENT_SAFARI_SOCKET` value.
- If native clicks fail, grant Accessibility permission to the app/terminal that launched the daemon or retry without native strict mode.
- Headless SSH sessions are not enough because the daemon controls a real WebKit window.
