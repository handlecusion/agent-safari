# Hermes Agent MCP setup

Use this example to connect Agent Safari to Hermes Agent through MCP.

## 1. Build or install

Homebrew:

```sh
brew tap handlecusion/agent-safari
brew install agent-safari
```

Source checkout:

```sh
git clone https://github.com/handlecusion/agent-safari.git
cd agent-safari
scripts/install_cli.sh
```

## 2. Start a daemon

```sh
agent-safari daemon --socket /tmp/agent-safari.sock
```

For source-development sessions you can use:

```sh
scripts/dev_restart.sh 'https://example.com'
```

## 3. Register with Hermes

Installed via Homebrew:

```sh
hermes mcp add agent-safari \
  --command python3 \
  --args /opt/homebrew/share/agent-safari/mcp/agent_safari_mcp.py \
  --env AGENT_SAFARI_BIN=/opt/homebrew/bin/agent-safari \
  --env AGENT_SAFARI_SOCKET=/tmp/agent-safari.sock

hermes mcp test agent-safari
```

Source checkout:

```sh
hermes mcp add agent-safari \
  --command "$PWD/.venv-mcp/bin/python" \
  --args "$PWD/mcp/agent_safari_mcp.py" \
  --env AGENT_SAFARI_BIN="$PWD/.build/debug/agent-safari" \
  --env AGENT_SAFARI_SOCKET=/tmp/agent-safari.sock

hermes mcp test agent-safari
```

Reload MCP servers in an active Hermes session with `/reload-mcp`, or start a new Hermes session.

## 4. Prompt pattern

```text
Use the agent-safari MCP tools to open https://example.com, call snapshot, click @e1 if it is safe, wait for idle, and capture a full-page screenshot.
```

## Notes

- `snapshot` returns compact refs such as `@e1`; pass those refs to `click` or `fill`.
- `network_start`, `network_list`, and `network_export` capture fetch/XHR activity with redaction controls.
- Use `observe` or `status` before acting when you need a cheap read-only browser state check.
