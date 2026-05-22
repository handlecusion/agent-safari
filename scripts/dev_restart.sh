#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOCKET="${AGENT_SAFARI_SOCKET:-/tmp/agent-safari.sock}"
URL="${1:-${AGENT_SAFARI_DEV_URL:-}}"
LOG_DIR="${AGENT_SAFARI_LOG_DIR:-$ROOT/.tmp}"
LOG_FILE="$LOG_DIR/agent-safari-daemon.log"
PID_FILE="$LOG_DIR/agent-safari-daemon.pid"

mkdir -p "$LOG_DIR"
cd "$ROOT"

printf '[dev_restart] build + install\n'
scripts/install_cli.sh

printf '[dev_restart] stop existing daemons\n'
if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid" 2>/dev/null || true
  fi
fi
pkill -f 'agent-safari daemon' 2>/dev/null || true
rm -f "$SOCKET"

printf '[dev_restart] start daemon socket=%s\n' "$SOCKET"
nohup agent-safari daemon --socket "$SOCKET" >"$LOG_FILE" 2>&1 &
pid=$!
printf '%s\n' "$pid" > "$PID_FILE"

for _ in {1..50}; do
  if [[ -S "$SOCKET" ]]; then
    break
  fi
  sleep 0.1
done

if [[ ! -S "$SOCKET" ]]; then
  printf '[dev_restart] ERROR: socket was not created: %s\n' "$SOCKET" >&2
  printf '[dev_restart] log: %s\n' "$LOG_FILE" >&2
  exit 1
fi

printf '[dev_restart] pid=%s log=%s\n' "$pid" "$LOG_FILE"

if [[ -n "$URL" ]]; then
  printf '[dev_restart] navigate %s\n' "$URL"
  agent-safari navigate "$URL" --socket "$SOCKET"
else
  agent-safari status --socket "$SOCKET"
fi

printf '[dev_restart] ready\n'
