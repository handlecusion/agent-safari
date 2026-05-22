#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${AGENT_SAFARI_BIN:-$ROOT_DIR/.build/debug/agent-safari}"
SOCKET="${AGENT_SAFARI_SOCKET:-/tmp/agent-safari-smoke.$$.sock}"
SMOKE_DIR="${AGENT_SAFARI_SMOKE_DIR:-$(mktemp -d /tmp/agent-safari-smoke.XXXXXX)}"
HTML="$SMOKE_DIR/smoke.html"
SHOT="$SMOKE_DIR/full-page.png"
DAEMON_PID=""

cleanup() {
  if [[ -n "$DAEMON_PID" ]] && kill -0 "$DAEMON_PID" 2>/dev/null; then
    kill "$DAEMON_PID" 2>/dev/null || true
    wait "$DAEMON_PID" 2>/dev/null || true
  fi
  rm -f "$SOCKET"
}
trap cleanup EXIT INT TERM

log() {
  printf '[smoke_cli] %s\n' "$*"
}

run_cli() {
  "$BIN" "$@" --socket "$SOCKET"
}

assert_ok_json() {
  python3 - "$1" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
if not payload.get("ok"):
    raise SystemExit(f"CLI response was not ok: {payload}")
PY
}

assert_result_field() {
  python3 - "$1" "$2" "$3" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
field = sys.argv[2]
expected = sys.argv[3]
actual = payload.get("result", {}).get(field)
if isinstance(actual, bool):
    actual_text = "true" if actual else "false"
else:
    actual_text = str(actual)
if actual_text != expected:
    raise SystemExit(f"Unexpected result.{field}: {actual!r} != {expected!r}; payload={payload}")
PY
}

assert_snapshot_ref_response() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
expected_ref = sys.argv[2]
selector = payload.get("result", {}).get("selector")
if selector != expected_ref or not expected_ref.startswith("@e"):
    raise SystemExit(f"CLI did not report use of snapshot ref {expected_ref!r}; selector={selector!r}; payload={payload}")
PY
}

assert_full_page_png() {
  python3 - "$1" "$2" <<'PY'
import json
import os
import struct
import sys

payload = json.loads(sys.argv[1])
expected_path = sys.argv[2]
result = payload.get("result", {})
path = result.get("path") or expected_path
if path != expected_path:
    raise SystemExit(f"Unexpected screenshot path metadata: {path!r} != {expected_path!r}")
full_page = result.get("fullPage")
if full_page not in ("true", True):
    raise SystemExit(f"Screenshot did not report fullPage=true: {payload}")
if not os.path.isfile(expected_path) or os.path.getsize(expected_path) <= 0:
    raise SystemExit(f"Screenshot missing or empty: {expected_path}")
with open(expected_path, "rb") as fh:
    header = fh.read(24)
if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
    raise SystemExit(f"Screenshot is not a valid PNG: {expected_path}")
png_width, png_height = struct.unpack(">II", header[16:24])
metadata_width = int(result["width"]) if result.get("width") else None
metadata_height = int(result["height"]) if result.get("height") else None
scale = 1.0
if metadata_width is not None and metadata_height is not None:
    if metadata_width <= 0 or metadata_height <= 0:
        raise SystemExit(f"Invalid screenshot metadata dimensions: {metadata_width}x{metadata_height}")
    width_scale = png_width / metadata_width
    height_scale = png_height / metadata_height
    if abs(width_scale - height_scale) > 0.01:
        raise SystemExit(
            f"PNG scale was inconsistent with metadata: png={png_width}x{png_height}, "
            f"metadata={metadata_width}x{metadata_height}"
        )
    scale = width_scale
    if metadata_height < 1500:
        raise SystemExit(f"Full-page metadata height too small: {metadata_height}")
if png_height < 1500:
    raise SystemExit(f"Full-page screenshot height too small: {png_height}")
if result.get("strategy") not in {"single-rect", "tiled-scroll"}:
    raise SystemExit(f"Unexpected full-page screenshot strategy: {result.get('strategy')!r}")
print(
    f"png={png_width}x{png_height} metadata={metadata_width}x{metadata_height} "
    f"scale={scale:.2f} strategy={result.get('strategy')} tiles={result.get('tiles', '')}"
)
PY
}

assert_network_events() {
  python3 - "$1" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
result = payload.get("result", {})
events_raw = result.get("events", [])
if isinstance(events_raw, str):
    events = json.loads(events_raw)
else:
    events = events_raw
types = {event.get("type") for event in events}
if "fetch" not in types or "xhr" not in types:
    raise SystemExit(f"Expected both fetch and xhr network events; saw types={types}; events={events}")
completed = [event for event in events if event.get("phase") in {"response", "error", "error-or-cancel"}]
if len(completed) < 2:
    raise SystemExit(f"Expected completed network events; events={events}")
fetch = next(event for event in events if event.get("type") == "fetch")
xhr = next(event for event in events if event.get("type") == "xhr")
if fetch.get("method") != "POST" or xhr.get("method") != "POST":
    raise SystemExit(f"Expected POST fetch/xhr events; events={events}")
print(f"network_events={len(events)} types={','.join(sorted(types))}")
PY
}

is_ok_json() {
  python3 - "$1" <<'PY'
import json
import sys
try:
    payload = json.loads(sys.argv[1])
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if payload.get("ok") else 1)
PY
}

extract_refs() {
  python3 - "$1" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
result = payload.get("result", {})
items = result.get("elements")
if items is None:
    snapshot_text = result.get("snapshot", "[]")
    items = json.loads(snapshot_text)
input_ref = next((item["ref"] for item in items if item.get("tag") in {"input", "textarea"}), None)
button_ref = next((item["ref"] for item in items if item.get("tag") == "button"), None)
if not input_ref or not button_ref:
    raise SystemExit(f"Could not find input and button refs in snapshot: {items}")
print(input_ref)
print(button_ref)
PY
}

wait_for_socket() {
  local deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    if [[ -S "$SOCKET" ]]; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

mkdir -p "$SMOKE_DIR"
cat > "$HTML" <<'HTML'
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>agent-safari CLI smoke</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 32px; }
    main { min-height: 1600px; }
    label, input, button, output { display: block; margin: 12px 0; }
  </style>
</head>
<body>
  <main>
    <h1>agent-safari CLI smoke</h1>
    <label for="name">Name</label>
    <input id="name" name="name" placeholder="type here">
    <button id="commit" type="button">Commit</button>
    <output id="status">waiting</output>
  </main>
  <script>
    document.getElementById('commit').addEventListener('click', () => {
      document.getElementById('status').textContent = 'clicked:' + document.getElementById('name').value;
    });

    window.runAgentSafariNetworkSmoke = async () => {
      const fetchUrl = 'data:application/json,%7B%22ok%22%3Atrue%2C%22kind%22%3A%22fetch%22%7D';
      await fetch(fetchUrl, { method: 'POST', body: 'fetch-smoke' }).catch(() => {});

      await new Promise((resolve) => {
        const xhr = new XMLHttpRequest();
        const xhrBlob = new Blob(['xhr-smoke'], { type: 'text/plain' });
        const xhrUrl = URL.createObjectURL(xhrBlob);
        const done = () => { URL.revokeObjectURL(xhrUrl); resolve(); };
        xhr.addEventListener('loadend', done, { once: true });
        xhr.addEventListener('error', done, { once: true });
        try {
          xhr.open('POST', xhrUrl);
          xhr.send('xhr-smoke');
        } catch (_) {
          done();
        }
      });

      document.getElementById('status').textContent = 'network:done';
      return true;
    };
  </script>
</body>
</html>
HTML

log "building Swift package"
(cd "$ROOT_DIR" && swift build)

log "starting daemon on $SOCKET"
rm -f "$SOCKET"
"$BIN" daemon --socket "$SOCKET" >"$SMOKE_DIR/daemon.log" 2>&1 &
DAEMON_PID=$!

if ! wait_for_socket; then
  log "daemon did not create socket; log follows"
  sed 's/^/[daemon] /' "$SMOKE_DIR/daemon.log" >&2 || true
  exit 1
fi

URL="file://$HTML"
log "navigating to $URL"
response="$(run_cli navigate "$URL")"
assert_ok_json "$response"

log "snapshotting interactive elements"
snapshot="$(run_cli snapshot)"
assert_ok_json "$snapshot"
refs_file="$SMOKE_DIR/refs.txt"
extract_refs "$snapshot" > "$refs_file"
{
  IFS= read -r INPUT_REF
  IFS= read -r BUTTON_REF
} < "$refs_file"
log "using refs input=$INPUT_REF button=$BUTTON_REF"

log "filling via snapshot ref"
response="$(run_cli fill "$INPUT_REF" "smoke-value")"
assert_ok_json "$response"
assert_snapshot_ref_response "$response" "$INPUT_REF"
assert_result_field "$response" "value" "smoke-value"

log "clicking via native Quartz snapshot ref"
response="$(run_cli click "$BUTTON_REF" --native)"
assert_ok_json "$response"
assert_snapshot_ref_response "$response" "$BUTTON_REF"

log "verifying wait commands"
response="$(run_cli wait 25)"
assert_ok_json "$response"
assert_result_field "$response" "waitedMs" "25"
response="$(run_cli wait-for-selector "#status" --timeout 2000)"
assert_ok_json "$response"
assert_result_field "$response" "found" "true"
response="$(run_cli wait-for-text "clicked:smoke-value" --timeout 2000)"
assert_ok_json "$response"
assert_result_field "$response" "found" "true"

log "verifying DOM state"
response="$(run_cli evaluate "document.getElementById('status').textContent")"
assert_ok_json "$response"
python3 - "$response" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
value = payload.get("result", {}).get("value")
if value != "clicked:smoke-value":
    raise SystemExit(f"Unexpected status text: {value!r}")
PY

log "capturing full-page screenshot"
response="$(run_cli screenshot-full "$SHOT")"
assert_ok_json "$response"
png_summary="$(assert_full_page_png "$response" "$SHOT")"
log "verified full-page screenshot $png_summary"

usage="$($BIN 2>&1 || true)"
if printf '%s\n' "$usage" | grep -E 'network-(start|stop)' >/dev/null; then
  log "network commands advertised; verifying network-start/list/stop capture fetch and XHR"
  response="$(run_cli network-start)"
  assert_ok_json "$response"
  response="$(run_cli evaluate "window.runAgentSafariNetworkSmoke && window.runAgentSafariNetworkSmoke(); true")"
  assert_ok_json "$response"
  response="$(run_cli wait-for-text "network:done" --timeout 5000)"
  assert_ok_json "$response"
  response="$(run_cli wait-for-idle --timeout 5000)"
  assert_ok_json "$response"
  response="$(run_cli network-list)"
  assert_ok_json "$response"
  network_summary="$(assert_network_events "$response")"
  log "verified network-list $network_summary"
  response="$(run_cli network-stop)"
  assert_ok_json "$response"
  assert_result_field "$response" "capturing" "false"
  network_summary="$(assert_network_events "$response")"
  log "verified network-stop $network_summary"
else
  log "network commands not advertised; skipping optional network smoke"
fi

log "ok"
log "artifacts: $SMOKE_DIR"
