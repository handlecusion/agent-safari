# agent-safari npm package

This npm package provides the `agent-safari` command for macOS.

On install, it downloads the matching GitHub Release binary asset for your macOS architecture and exposes it as:

```sh
npx agent-safari status
npx agent-safari daemon --socket /tmp/agent-safari.sock
```

Requirements:

- macOS
- Node.js 18+
- A published `agent-safari` GitHub Release matching the npm package version

Development override:

```sh
AGENT_SAFARI_BIN=/path/to/.build/release/agent-safari npx agent-safari status
```

Skip binary download for packaging tests:

```sh
AGENT_SAFARI_SKIP_DOWNLOAD=1 npm install
```
