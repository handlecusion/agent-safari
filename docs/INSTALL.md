# Installation

This guide covers the supported ways to install `agent-safari` and connect it to MCP clients.

`agent-safari` is macOS-only. It controls a real native WebKit/WKWebView window, so it must run inside a logged-in macOS GUI session.

## Requirements

- macOS with GUI access.
- Swift toolchain when building from source or installing through Homebrew.
- Python 3 when using the MCP wrapper.
- Optional: macOS Accessibility permission for strict native click verification.

Headless SSH-only sessions are not sufficient because the daemon owns a visible WebKit window.

## Option 1: Homebrew, recommended

```sh
brew tap handlecusion/agent-safari
brew install agent-safari
```

The public tap is:

- https://github.com/handlecusion/homebrew-agent-safari

Verify the CLI is available:

```sh
agent-safari --help
```

Optionally register the MCP wrapper with detected AI agents:

```sh
agent-safari-mcp-setup --dry-run
agent-safari-mcp-setup
```

The setup helper detects Claude Desktop, Cursor, Windsurf, VS Code, and Hermes Agent config locations. It prints the MCP server config and asks for approval before writing each config file.

Start the daemon:

```sh
agent-safari daemon --socket /tmp/agent-safari.sock
```

Then drive it from another terminal:

```sh
agent-safari open 'https://example.com' --socket /tmp/agent-safari.sock
agent-safari snapshot --socket /tmp/agent-safari.sock
```

## Option 2: GitHub Release binary

Download the latest release from:

- https://github.com/handlecusion/agent-safari/releases

Current macOS ARM64 example:

```sh
curl -L -o /tmp/agent-safari-v0.0.4-macOS-ARM64.zip \
  https://github.com/handlecusion/agent-safari/releases/download/v0.0.4/agent-safari-v0.0.4-macOS-ARM64.zip
unzip /tmp/agent-safari-v0.0.4-macOS-ARM64.zip -d /tmp
/tmp/agent-safari-v0.0.4-macOS-ARM64/install.sh
```

The installer copies the native binary and setup helper to:

```text
${PREFIX:-$HOME/.local}/bin/agent-safari
${PREFIX:-$HOME/.local}/bin/agent-safari-mcp-setup
```

It also installs the MCP wrapper under `${PREFIX:-$HOME/.local}/share/agent-safari/mcp/`.

If `agent-safari` is not found after install, add the install directory to your shell profile:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## Option 3: Build from source

```sh
git clone https://github.com/handlecusion/agent-safari.git
cd agent-safari
scripts/install_cli.sh
```

By default the installer builds a debug binary and symlinks it into `~/.local/bin`:

```text
~/.local/bin/agent-safari -> <repo>/.build/debug/agent-safari
```

For a release build from source:

```sh
AGENT_SAFARI_BUILD_CONFIGURATION=release scripts/install_cli.sh
```

You can change the install directory:

```sh
AGENT_SAFARI_INSTALL_DIR=/usr/local/bin scripts/install_cli.sh
```

## npm status

The npm wrapper is implemented in `npm/agent-safari`, but the public npm package is not published yet. Until npm publishing is enabled, use Homebrew, GitHub Releases, or source build.

## Start and control the daemon

Start the browser daemon:

```sh
agent-safari daemon --socket /tmp/agent-safari.sock
```

Useful options:

```sh
agent-safari daemon --focus-window --socket /tmp/agent-safari.sock
agent-safari daemon --profile work --socket /tmp/agent-safari-work.sock
agent-safari daemon --ephemeral --socket /tmp/agent-safari-ephemeral.sock
```

Control it from another terminal:

```sh
agent-safari status --socket /tmp/agent-safari.sock
agent-safari open 'https://example.com' --socket /tmp/agent-safari.sock
agent-safari snapshot --socket /tmp/agent-safari.sock
agent-safari click '@e1' --native --socket /tmp/agent-safari.sock
agent-safari screenshot --full --out /tmp/agent-safari-full.png --socket /tmp/agent-safari.sock
```

All client commands accept `--socket <path>`. The default socket is `/tmp/agent-safari.sock`.

## MCP setup

The MCP server is a Python stdio wrapper around the Swift CLI. The daemon must be running before MCP tools can control the browser.

### Consent-first agent setup helper

Homebrew and source installs include:

```sh
agent-safari-mcp-setup
```

The helper follows the same user-consent pattern used by browser MCP installers: it detects known local agent config locations, shows the MCP server entry, then asks before writing each config file. Supported targets:

- Claude Desktop: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Cursor: `~/.cursor/mcp.json`
- Windsurf: `~/.codeium/windsurf/mcp_config.json`
- VS Code: `~/Library/Application Support/Code/User/mcp.json`
- Hermes Agent: `~/.hermes/config.yaml`

Preview without writing:

```sh
agent-safari-mcp-setup --dry-run
```

Apply to every detected target without prompts, useful in scripts after you have inspected the dry run:

```sh
agent-safari-mcp-setup --yes
```

Limit setup to one target:

```sh
agent-safari-mcp-setup --agent claude-desktop
agent-safari-mcp-setup --agent hermes
```

### Source checkout MCP setup

From a source checkout:

```sh
python3 -m venv .venv-mcp
.venv-mcp/bin/python -m pip install -r mcp/requirements.txt
AGENT_SAFARI_BIN="$PWD/.build/debug/agent-safari" \
AGENT_SAFARI_SOCKET=/tmp/agent-safari.sock \
.venv-mcp/bin/python mcp/agent_safari_mcp.py --check
```

Typical MCP host config:

```json
{
  "mcpServers": {
    "agent-safari": {
      "command": "python3",
      "args": ["/path/to/agent-safari/mcp/agent_safari_mcp.py"],
      "env": {
        "AGENT_SAFARI_BIN": "/path/to/agent-safari/.build/debug/agent-safari",
        "AGENT_SAFARI_SOCKET": "/tmp/agent-safari.sock"
      }
    }
  }
}
```

### Hermes example

```sh
hermes mcp add agent-safari \
  --command "$PWD/.venv-mcp/bin/python" \
  --args "$PWD/mcp/agent_safari_mcp.py" \
  --env AGENT_SAFARI_BIN="$PWD/.build/debug/agent-safari" \
  --env AGENT_SAFARI_SOCKET=/tmp/agent-safari.sock

hermes mcp test agent-safari
```

After changing MCP config in an active Hermes session, reload MCP servers with `/reload-mcp` or start a fresh session.

## Development restart helper

From a source checkout:

```sh
scripts/dev_restart.sh
scripts/dev_restart.sh 'https://www.google.com'
```

This rebuilds, reinstalls, stops any existing daemon for the selected socket, starts a new daemon, and optionally navigates to the provided URL.

Defaults:

- Socket: `/tmp/agent-safari.sock`
- Log file: `.tmp/agent-safari-daemon.log`
- PID file: `.tmp/agent-safari-daemon.pid`

Override the socket:

```sh
AGENT_SAFARI_SOCKET=/tmp/custom.sock scripts/dev_restart.sh
```

## Troubleshooting

### `agent-safari` command not found

Make sure your install directory is on `PATH`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

For Homebrew installs, check:

```sh
brew --prefix
which agent-safari
```

### Swift toolchain missing

Install Xcode or Command Line Tools, then retry:

```sh
xcode-select --install
swift --version
```

### Daemon cannot be reached

Check that the daemon is running and that client commands use the same socket path:

```sh
agent-safari status --socket /tmp/agent-safari.sock
```

Use a short socket path under `/tmp`; Unix socket paths have platform length limits.

### Native click verification is flaky

Native click verification requires a logged-in GUI session and, for strict native input flows, macOS Accessibility permission for the app or terminal that runs the daemon. You can still use DOM click fallback unless you pass `--no-fallback`.

### MCP tools load but browser actions fail

Confirm all three are true:

1. The daemon is running.
2. `AGENT_SAFARI_BIN` points to an executable `agent-safari` binary.
3. `AGENT_SAFARI_SOCKET` matches the daemon socket.

Run:

```sh
python3 mcp/agent_safari_mcp.py --check
```

See also `docs/MCP_WRAPPER.md`.
