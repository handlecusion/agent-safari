#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_NAME="agent-safari"
MCP_SETUP_NAME="agent-safari-mcp-setup"
CONFIGURATION="${AGENT_SAFARI_BUILD_CONFIGURATION:-debug}"
INSTALL_DIR="${AGENT_SAFARI_INSTALL_DIR:-$HOME/.local/bin}"

case "$CONFIGURATION" in
  debug)
    BUILT_BIN="$ROOT/.build/debug/$BIN_NAME"
    ;;
  release)
    BUILT_BIN="$ROOT/.build/release/$BIN_NAME"
    ;;
  *)
    echo "Unsupported AGENT_SAFARI_BUILD_CONFIGURATION=$CONFIGURATION; use debug or release" >&2
    exit 2
    ;;
esac

echo "[install_cli] building $BIN_NAME ($CONFIGURATION)"
if [[ "$CONFIGURATION" == "release" ]]; then
  swift build -c release --package-path "$ROOT"
else
  swift build --package-path "$ROOT"
fi

if [[ ! -x "$BUILT_BIN" ]]; then
  echo "Built binary not found or not executable: $BUILT_BIN" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
TARGET="$INSTALL_DIR/$BIN_NAME"

if [[ -e "$TARGET" && ! -L "$TARGET" ]]; then
  echo "Refusing to overwrite non-symlink: $TARGET" >&2
  echo "Set AGENT_SAFARI_INSTALL_DIR to another directory or move the existing file." >&2
  exit 1
fi

ln -sfn "$BUILT_BIN" "$TARGET"
chmod +x "$BUILT_BIN"

MCP_SETUP_TARGET="$INSTALL_DIR/$MCP_SETUP_NAME"
if [[ -e "$MCP_SETUP_TARGET" && ! -L "$MCP_SETUP_TARGET" ]]; then
  echo "Refusing to overwrite non-symlink: $MCP_SETUP_TARGET" >&2
  echo "Set AGENT_SAFARI_INSTALL_DIR to another directory or move the existing file." >&2
  exit 1
fi
ln -sfn "$ROOT/scripts/agent_safari_mcp_setup.py" "$MCP_SETUP_TARGET"
chmod +x "$ROOT/scripts/agent_safari_mcp_setup.py"

echo "[install_cli] installed: $TARGET -> $BUILT_BIN"
echo "[install_cli] installed: $MCP_SETUP_TARGET -> $ROOT/scripts/agent_safari_mcp_setup.py"
if command -v "$BIN_NAME" >/dev/null 2>&1; then
  RESOLVED="$(command -v "$BIN_NAME")"
  echo "[install_cli] command resolves to: $RESOLVED"
else
  echo "[install_cli] WARNING: $INSTALL_DIR is not on PATH for this shell."
  echo "Add this to your shell rc file: export PATH=\"$INSTALL_DIR:\$PATH\""
fi
