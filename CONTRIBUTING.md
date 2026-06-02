# Contributing to agent-safari

Thanks for helping improve Agent Safari. This project is a local-first macOS Safari/WebKit automation CLI, daemon, and MCP server for AI agents.

## Scope

Good contributions:

- Agent-friendly browser observation and control.
- CLI/MCP parity improvements.
- WebKit screenshot, snapshot, wait, tab, profile, and network-capture reliability.
- Installation, packaging, docs, examples, and smoke-test improvements.

Out of scope for the current roadmap:

- Passkey/WebAuthn automation.
- Vendoring third-party dependencies into the repository.
- Browser-cloud or remote-hosted automation services.

## Local setup

```sh
git clone https://github.com/handlecusion/agent-safari.git
cd agent-safari
scripts/install_cli.sh
```

Start a development daemon:

```sh
scripts/dev_restart.sh 'https://example.com'
```

## Checks before opening a PR

Run the cheapest relevant checks first:

```sh
swift test
python3 -m pytest Tests
```

For CLI/MCP behavior changes, also run:

```sh
scripts/smoke_cli.sh
AGENT_SAFARI_BIN="$PWD/.build/debug/agent-safari" \
AGENT_SAFARI_SOCKET=/tmp/agent-safari.sock \
python3 scripts/smoke_mcp_wrapper.py
```

For release-impacting changes, use the checklist in `docs/RELEASE_CHECKLIST.md`.

## Development guidelines

- Keep every CLI command returning one JSON response line.
- Keep MCP tools aligned with CLI behavior when browser-control commands change.
- Prefer structured errors over free-form text.
- Do not log secrets, cookies, authorization headers, or raw request bodies by default.
- Preserve snapshot ref workflows such as `@e1` for agent loops.
- Document limitations clearly when a feature is intentionally partial, especially network capture and native input.

## Pull request checklist

- [ ] The change has a focused title and description.
- [ ] User-facing CLI/MCP behavior is documented.
- [ ] Tests or smoke checks cover the changed path where practical.
- [ ] Packaging/docs are updated if install paths, commands, or release artifacts change.
- [ ] Known limitations are stated honestly.

## Reporting issues

When filing an issue, include:

- macOS version and CPU architecture.
- Install method: Homebrew, GitHub Release, or source build.
- Exact command or MCP client config used.
- Daemon socket path.
- Relevant JSON output or redacted logs.
- Whether the daemon was running in a logged-in GUI session.
