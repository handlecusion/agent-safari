#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${AGENT_SAFARI_VERSION:-}"
DEST_DIR="${AGENT_SAFARI_DIST_DIR:-$ROOT_DIR/.tmp/dist}"
PACKAGE_SRC="$ROOT_DIR/npm/agent-safari"
WORK_DIR="$ROOT_DIR/.tmp/npm-package"

if [[ -z "$VERSION" || ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9][A-Za-z0-9.-]*)?$ ]]; then
  printf 'AGENT_SAFARI_VERSION must be vMAJOR.MINOR.PATCH[-PRERELEASE], got: %s\n' "${VERSION:-<empty>}" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  printf 'npm is required to package the npm distribution\n' >&2
  exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$DEST_DIR"
cp -R "$PACKAGE_SRC"/. "$WORK_DIR"/
python3 - "$WORK_DIR/package.json" "${VERSION#v}" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
version = sys.argv[2]
data = json.loads(path.read_text(encoding="utf-8"))
data["version"] = version
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

(
  cd "$WORK_DIR"
  npm pack --pack-destination "$DEST_DIR"
)
