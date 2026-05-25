#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${AGENT_SAFARI_BIN:-$ROOT_DIR/.build/release/agent-safari}"
RAW_VERSION="${AGENT_SAFARI_VERSION:-$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || true)}"
if [[ -z "$RAW_VERSION" || ! "$RAW_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9][A-Za-z0-9.-]*)?$ ]]; then
  if [[ -n "${AGENT_SAFARI_VERSION:-}" ]]; then
    printf 'invalid AGENT_SAFARI_VERSION: %s\n' "$AGENT_SAFARI_VERSION" >&2
    printf 'expected format: vMAJOR.MINOR.PATCH[-PRERELEASE]\n' >&2
    exit 1
  fi
  SHORT_SHA="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo local)"
  DIRTY_SUFFIX=""
  if ! git -C "$ROOT_DIR" diff --quiet --ignore-submodules -- 2>/dev/null; then
    DIRTY_SUFFIX=".dirty"
  fi
  VERSION="v0.0.0-dev.${SHORT_SHA}${DIRTY_SUFFIX}"
else
  VERSION="$RAW_VERSION"
fi
RUNNER_OS_NAME="${RUNNER_OS:-macos}"
RUNNER_ARCH_NAME="${RUNNER_ARCH:-$(uname -m)}"
for label in RUNNER_OS_NAME RUNNER_ARCH_NAME; do
  value="${!label}"
  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'invalid %s: %s\n' "$label" "$value" >&2
    exit 1
  fi
done
DIST_DIR_RAW="${AGENT_SAFARI_DIST_DIR:-$ROOT_DIR/.tmp/dist}"
mkdir -p "$DIST_DIR_RAW"
DIST_DIR="$(cd "$DIST_DIR_RAW" && pwd)"
STAGING_DIR="$DIST_DIR/agent-safari-$VERSION-$RUNNER_OS_NAME-$RUNNER_ARCH_NAME"
ARCHIVE="$DIST_DIR/agent-safari-$VERSION-$RUNNER_OS_NAME-$RUNNER_ARCH_NAME.zip"
CHECKSUMS="$DIST_DIR/checksums.txt"

if [[ ! -x "$BINARY" ]]; then
  printf 'release binary not found or not executable: %s\n' "$BINARY" >&2
  printf 'run swift build -c release first, or set AGENT_SAFARI_BIN.\n' >&2
  exit 1
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/docs" "$STAGING_DIR/mcp" "$STAGING_DIR/scripts" "$DIST_DIR"

cp "$BINARY" "$STAGING_DIR/bin/agent-safari"
cp "$ROOT_DIR/README.md" "$ROOT_DIR/LICENSE" "$STAGING_DIR/"
cp "$ROOT_DIR/docs/INSTALL.md" "$ROOT_DIR/docs/MCP_WRAPPER.md" "$STAGING_DIR/docs/"
cp "$ROOT_DIR/mcp/agent_safari_mcp.py" "$STAGING_DIR/mcp/"
cp "$ROOT_DIR/scripts/install_cli.sh" "$ROOT_DIR/scripts/dev_restart.sh" "$ROOT_DIR/scripts/agent_safari_mcp_setup.py" "$STAGING_DIR/scripts/"

cat > "$STAGING_DIR/install.sh" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$PREFIX/bin"
mkdir -p "$PREFIX/share/agent-safari/mcp"
cp "$ROOT/bin/agent-safari" "$PREFIX/bin/agent-safari"
cp "$ROOT/scripts/agent_safari_mcp_setup.py" "$PREFIX/bin/agent-safari-mcp-setup"
cp "$ROOT/mcp/agent_safari_mcp.py" "$PREFIX/share/agent-safari/mcp/agent_safari_mcp.py"
chmod +x "$PREFIX/bin/agent-safari"
chmod +x "$PREFIX/bin/agent-safari-mcp-setup"
printf 'installed %s\n' "$PREFIX/bin/agent-safari"
printf 'installed %s\n' "$PREFIX/bin/agent-safari-mcp-setup"
printf 'installed %s\n' "$PREFIX/share/agent-safari/mcp/agent_safari_mcp.py"
INSTALL
chmod +x "$STAGING_DIR/install.sh" "$STAGING_DIR/bin/agent-safari"
chmod +x "$STAGING_DIR/scripts/agent_safari_mcp_setup.py"

(
  cd "$DIST_DIR"
  rm -f "$(basename "$ARCHIVE")"
  zip -qry "$(basename "$ARCHIVE")" "$(basename "$STAGING_DIR")"
  shasum -a 256 "$(basename "$ARCHIVE")" > "$CHECKSUMS"
)

printf '%s\n' "$ARCHIVE"
printf '%s\n' "$CHECKSUMS"
