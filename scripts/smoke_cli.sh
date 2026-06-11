#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${AGENT_SAFARI_BIN:-$ROOT_DIR/.build/debug/agent-safari}"
SOCKET="${AGENT_SAFARI_SOCKET:-/tmp/agent-safari-smoke.$$.sock}"
SMOKE_DIR="${AGENT_SAFARI_SMOKE_DIR:-$(mktemp -d /tmp/agent-safari-smoke.XXXXXX)}"
HTML="$SMOKE_DIR/smoke.html"
SHOT="$SMOKE_DIR/full-page.png"
ELEMENT_SHOT="$SMOKE_DIR/element.png"
NETWORK_EXPORT="$SMOKE_DIR/network.har.json"
UPLOAD_FILE="$SMOKE_DIR/upload-sample.txt"
DOWNLOAD_SERVER="$SMOKE_DIR/download_server.py"
DOWNLOAD_PORT_FILE="$SMOKE_DIR/download_port.txt"
DAEMON_PID=""
DOWNLOAD_SERVER_PID=""

cleanup() {
  if [[ -n "$DOWNLOAD_SERVER_PID" ]] && kill -0 "$DOWNLOAD_SERVER_PID" 2>/dev/null; then
    kill "$DOWNLOAD_SERVER_PID" 2>/dev/null || true
    wait "$DOWNLOAD_SERVER_PID" 2>/dev/null || true
  fi
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

assert_console_events() {
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
count = result.get("count", 0)
if isinstance(count, str):
    count = int(count)
if count < 2:
    raise SystemExit(f"Expected at least 2 console events; got count={count}; events={events}")
error_events = [e for e in events if e.get("type") in {"console", "error", "unhandledrejection"} and e.get("level") == "error"]
if not error_events:
    raise SystemExit(f"Expected at least one level=error event; events={events}")
marker_events = [e for e in events if "agent-safari-console-smoke-marker" in str(e.get("message", ""))]
if not marker_events:
    raise SystemExit(f"Expected console.error marker event; events={events}")
print(f"console_events={len(events)} error_events={len(error_events)}")
PY
}

assert_console_isolation() {
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
tab1_leak = [e for e in events if "tab1-isolation-error" in str(e.get("message", ""))]
if tab1_leak:
    raise SystemExit(f"console capture leaked across tabs; tab-2 saw tab-1 events: {tab1_leak}")
print(f"per-tab isolation verified: tab-2 events={len(events)} no tab-1 leak")
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
    <input type="file" id="upload" name="upload">
    <output id="upload-status">no-upload</output>
  </main>
  <script>
    document.getElementById('commit').addEventListener('click', () => {
      document.getElementById('status').textContent = 'clicked:' + document.getElementById('name').value;
    });
    document.getElementById('upload').addEventListener('change', () => {
      const input = document.getElementById('upload');
      const first = input.files[0] ? input.files[0].name : '';
      document.getElementById('upload-status').textContent = 'uploaded:' + input.files.length + ':' + first;
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

    window.runAgentSafariConsoleSmoke = async () => {
      console.error('agent-safari-console-smoke-marker');
      setTimeout(function() { throw new Error('agent-safari-uncaught-error'); }, 0);
      Promise.reject(new Error('agent-safari-unhandled-rejection'));
      document.getElementById('status').textContent = 'console:done';
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
log "opening $URL via normalized CLI alias"
response="$(run_cli open "$URL")"
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

log "verifying file upload validation and open-panel delivery"
printf 'agent-safari upload smoke\n' > "$UPLOAD_FILE"
# Deterministic validation failures fire regardless of GUI/headless environment.
response="$(run_cli upload "#upload" "$SMOKE_DIR/missing-file.txt" || true)"
python3 - "$response" <<'UPLOADPY'
import json, sys
payload = json.loads(sys.argv[1])
if payload.get("ok") or payload.get("error", {}).get("code") != "upload_file_not_found":
    raise SystemExit(f"expected upload_file_not_found error: {payload}")
UPLOADPY
response="$(run_cli upload "#upload" "$UPLOAD_FILE" "$UPLOAD_FILE" || true)"
python3 - "$response" <<'UPLOADPY'
import json, sys
payload = json.loads(sys.argv[1])
if payload.get("ok") or payload.get("error", {}).get("code") != "upload_multiple_not_allowed":
    raise SystemExit(f"expected upload_multiple_not_allowed error: {payload}")
UPLOADPY
# Open-panel delivery uses a native Quartz click (real user activation), so it
# carries the same GUI-session requirement as the click --native smoke above.
response="$(run_cli upload "#upload" "$UPLOAD_FILE")"
assert_ok_json "$response"
python3 - "$response" <<'UPLOADPY'
import json, sys
payload = json.loads(sys.argv[1])
result = payload.get("result", {})
if str(result.get("fileCount")) != "1":
    raise SystemExit(f"upload fileCount != 1: {result}")
files_raw = result.get("files", "[]")
files = json.loads(files_raw) if isinstance(files_raw, str) else files_raw
if files != ["upload-sample.txt"]:
    raise SystemExit(f"unexpected upload files metadata: {result}")
print(f"upload set files via method={result.get('method')}")
UPLOADPY

log "capturing full-page screenshot"
response="$(run_cli screenshot --full --out "$SHOT")"
assert_ok_json "$response"
png_summary="$(assert_full_page_png "$response" "$SHOT")"
log "verified full-page screenshot $png_summary"

log "capturing element screenshot"
response="$(run_cli screenshot-element "$BUTTON_REF" --out "$ELEMENT_SHOT")"
assert_ok_json "$response"
python3 - "$response" "$ELEMENT_SHOT" <<'PY'
import json, os, sys
payload = json.loads(sys.argv[1])
path = payload.get('result', {}).get('path')
if path != sys.argv[2] or not os.path.isfile(path) or os.path.getsize(path) <= 0:
    raise SystemExit(f"element screenshot missing or empty: {payload}")
PY

log "verifying tab/session model"
response="$(run_cli session)"
assert_ok_json "$response"
assert_result_field "$response" "tabCount" "1"
response="$(run_cli tab-new "$URL")"
assert_ok_json "$response"
assert_result_field "$response" "created" "true"
response="$(run_cli tabs)"
assert_ok_json "$response"
python3 - "$response" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
tabs = payload.get('result', {}).get('tabs', [])
if len(tabs) < 2 or not any(tab.get('active') for tab in tabs):
    raise SystemExit(f"expected at least two modeled tabs with one active: {payload}")
PY

log "verifying same-document (fragment) navigation returns instead of hanging"
response="$(run_cli navigate "$URL#anchor-smoke")"
assert_ok_json "$response"
assert_result_field "$response" "sameDocument" "true"
assert_result_field "$response" "url" "$URL#anchor-smoke"
log "verifying full cross-document navigation still uses the load path"
response="$(run_cli navigate "$URL?side=left")"
assert_ok_json "$response"
assert_result_field "$response" "url" "$URL?side=left"
python3 - "$response" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
if "sameDocument" in payload.get("result", {}):
    raise SystemExit(f"full navigation should not report sameDocument: {payload}")
PY

log "verifying parallel multi-tab targeting"
response="$(run_cli tab-switch tab-1)"
assert_ok_json "$response"
response="$(run_cli title --tab tab-2)"
assert_ok_json "$response"
assert_result_field "$response" "tabId" "tab-2"
response="$(run_cli title --tab tab-99 || true)"
python3 - "$response" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
if payload.get("ok") or payload.get("error", {}).get("code") != "unknown_tab":
    raise SystemExit(f"expected unknown_tab error: {payload}")
PY
run_cli wait-for-selector '#never-exists' --timeout 6000 --tab tab-1 >/dev/null 2>&1 &
WAIT_PID=$!
sleep 0.3
START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
response="$(run_cli title --tab tab-2)"
ELAPSED_MS=$(python3 -c "import time; print(int(time.time()*1000) - $START_MS)")
assert_ok_json "$response"
if [ "$ELAPSED_MS" -ge 3000 ]; then
  log "tab-2 command blocked behind tab-1 wait (${ELAPSED_MS}ms)"
  exit 1
fi
log "verified tab-2 command returned in ${ELAPSED_MS}ms while tab-1 wait was running"
run_cli navigate "$URL?side=left" --tab tab-1 >/dev/null &
NAV1_PID=$!
run_cli navigate "$URL?side=right" --tab tab-2 >/dev/null &
NAV2_PID=$!
wait "$NAV1_PID" "$NAV2_PID"
response="$(run_cli url --tab tab-1)"
python3 - "$response" "side=left" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
if sys.argv[2] not in payload.get("result", {}).get("url", ""):
    raise SystemExit(f"parallel navigate landed on wrong tab: {payload}")
PY
response="$(run_cli url --tab tab-2)"
python3 - "$response" "side=right" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
if sys.argv[2] not in payload.get("result", {}).get("url", ""):
    raise SystemExit(f"parallel navigate landed on wrong tab: {payload}")
PY
wait "$WAIT_PID" || true
log "verified parallel navigates landed on their own tabs"

usage="$($BIN 2>&1 || true)"
if printf '%s\n' "$usage" | grep -E 'network( |$)|network-(start|stop)' >/dev/null; then
  log "network commands advertised; verifying normalized network start/list/stop capture fetch and XHR"
  response="$(run_cli network start)"
  assert_ok_json "$response"
  response="$(run_cli evaluate "window.runAgentSafariNetworkSmoke && window.runAgentSafariNetworkSmoke(); true")"
  assert_ok_json "$response"
  response="$(run_cli wait-for-text "network:done" --timeout 5000)"
  assert_ok_json "$response"
  response="$(run_cli wait-for-idle --timeout 5000)"
  assert_ok_json "$response"
  response="$(run_cli network list)"
  assert_ok_json "$response"
  network_summary="$(assert_network_events "$response")"
  log "verified network-list $network_summary"
  response="$(run_cli network export "$NETWORK_EXPORT" --max-entries 25 --body-preview-bytes 256)"
  assert_ok_json "$response"
  assert_result_field "$response" "schema" "har-like"
  python3 - "$NETWORK_EXPORT" <<'PY'
import json, sys
artifact = json.load(open(sys.argv[1]))
if artifact.get('log', {}).get('version') != '1.2' or not isinstance(artifact.get('log', {}).get('entries'), list):
    raise SystemExit(f"not a HAR-like export: {artifact}")
if artifact.get('agentSafari', {}).get('schemaVersion') != 1:
    raise SystemExit(f"missing agentSafari schema metadata: {artifact}")
PY
  response="$(run_cli network stop)"
  assert_ok_json "$response"
  assert_result_field "$response" "capturing" "false"
  network_summary="$(assert_network_events "$response")"
  log "verified network-stop $network_summary"
else
  log "network commands not advertised; skipping optional network smoke"
fi

usage_console="$($BIN 2>&1 || true)"
if printf '%s\n' "$usage_console" | grep -E 'console( |$)|console-(start|stop)' >/dev/null; then
  log "console commands advertised; verifying console start/list/stop captures errors"
  response="$(run_cli tab-switch tab-1)"
  assert_ok_json "$response"
  response="$(run_cli console start)"
  assert_ok_json "$response"
  assert_result_field "$response" "capturing" "true"
  response="$(run_cli evaluate "window.runAgentSafariConsoleSmoke && window.runAgentSafariConsoleSmoke(); true")"
  assert_ok_json "$response"
  response="$(run_cli wait-for-text "console:done" --timeout 5000)"
  assert_ok_json "$response"
  response="$(run_cli wait 300)"
  assert_ok_json "$response"
  response="$(run_cli console list)"
  assert_ok_json "$response"
  assert_console_events "$response"
  log "verified console-list captured >=2 events including type=error with marker"
  response="$(run_cli console stop)"
  assert_ok_json "$response"
  assert_result_field "$response" "capturing" "false"
  log "verified console-stop"
  log "verifying per-tab console isolation: start on tab-2, errors on tab-1 must not appear"
  response="$(run_cli tab-switch tab-2)"
  assert_ok_json "$response"
  response="$(run_cli console start --tab tab-2)"
  assert_ok_json "$response"
  response="$(run_cli evaluate "console.error('tab1-isolation-error'); true" --tab tab-1)"
  assert_ok_json "$response"
  response="$(run_cli console list --tab tab-2)"
  assert_ok_json "$response"
  assert_console_isolation "$response"
  log "verified per-tab console isolation"
  response="$(run_cli console stop --tab tab-2)"
  assert_ok_json "$response"
else
  log "console commands not advertised; skipping optional console smoke"
fi

log "verifying download handling: attachment navigate + download-link click do not hang and write files"
cat > "$DOWNLOAD_SERVER" <<'PYSERVER'
import http.server, socketserver, sys

PORT_FILE = sys.argv[1]
PAYLOAD = b"AGENT-SAFARI-SMOKE-DOWNLOAD-PAYLOAD\n"

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_GET(self):
        if self.path in ("/file.bin", "/file2.bin"):
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", 'attachment; filename="smoke-download.bin"')
            self.send_header("Content-Length", str(len(PAYLOAD)))
            self.end_headers()
            self.wfile.write(PAYLOAD)
        elif self.path == "/page.html":
            body = (b'<!doctype html><html><body>'
                    b'<a id="dl" download="clicked-download.txt" '
                    b'href="data:text/plain,AGENT-SAFARI-SMOKE-DOWNLOAD-PAYLOAD">download link</a>'
                    b'</body></html>')
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(PORT_FILE, "w") as fh:
        fh.write(str(httpd.server_address[1]))
    httpd.serve_forever()
PYSERVER

rm -f "$DOWNLOAD_PORT_FILE"
python3 "$DOWNLOAD_SERVER" "$DOWNLOAD_PORT_FILE" &
DOWNLOAD_SERVER_PID=$!
download_deadline=$((SECONDS + 15))
while (( SECONDS < download_deadline )); do
  [[ -s "$DOWNLOAD_PORT_FILE" ]] && break
  sleep 0.2
done
if [[ ! -s "$DOWNLOAD_PORT_FILE" ]]; then
  log "download server did not report a port"
  exit 1
fi
DOWNLOAD_PORT="$(cat "$DOWNLOAD_PORT_FILE")"
log "download server on 127.0.0.1:$DOWNLOAD_PORT"

assert_download_completed() {
  python3 - "$1" "AGENT-SAFARI-SMOKE-DOWNLOAD-PAYLOAD" <<'PY'
import json
import os
import sys
payload = json.loads(sys.argv[1])
expected_marker = sys.argv[2]
result = payload.get("result", {})
if not payload.get("ok"):
    raise SystemExit(f"download wait was not ok: {payload}")
if result.get("state") != "completed":
    raise SystemExit(f"download did not complete: {payload}")
path = result.get("path")
if not path or not os.path.isfile(path) or os.path.getsize(path) <= 0:
    raise SystemExit(f"download file missing or empty: {path!r}; payload={payload}")
with open(path, "rb") as fh:
    data = fh.read()
if expected_marker.encode() not in data:
    raise SystemExit(f"download bytes did not match expected payload: {data!r}")
print(f"download_path={path} bytes={len(data)} state={result.get('state')}")
PY
}

assert_download_started() {
  python3 - "$1" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
result = payload.get("result", {})
if not payload.get("ok"):
    raise SystemExit(f"command was not ok: {payload}")
if str(result.get("downloadStarted")).lower() != "true" or not result.get("downloadId"):
    raise SystemExit(f"expected downloadStarted/downloadId evidence: {payload}")
print(f"downloadId={result.get('downloadId')}")
PY
}

# Run the click case first on a clean tab history. Navigating directly to a download
# URL leaves the tab's current entry on that URL; clicking a link back to the same URL
# afterwards can be deduplicated by WebKit, so the two cases use independent tabs.
log "click on a download link reports downloadStarted instead of a silent no-op"
response="$(run_cli navigate "http://127.0.0.1:$DOWNLOAD_PORT/page.html")"
assert_ok_json "$response"
response="$(run_cli wait-for-selector '#dl' --timeout 5000)"
assert_ok_json "$response"
response="$(run_cli click '#dl')"
assert_ok_json "$response"
click_download="$(assert_download_started "$response")"
log "click download evidence: $click_download"
response="$(run_cli wait-for-download --last --timeout 8000)"
click_completed="$(assert_download_completed "$response")"
log "click download completed: $click_completed"

# Use a fresh tab so the navigate runs against clean history (a download leaves the tab's
# current entry on the download URL, which can dedup a later same-tab download navigation).
log "navigate to attachment URL returns downloadStarted instead of hanging or erroring"
response="$(run_cli tab-new)"
assert_ok_json "$response"
download_tab="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['result']['id'])" "$response")"
response="$(run_cli navigate "http://127.0.0.1:$DOWNLOAD_PORT/file2.bin" --tab "$download_tab")"
assert_ok_json "$response"
nav_download="$(assert_download_started "$response")"
log "navigate download evidence on $download_tab: $nav_download"
response="$(run_cli wait-for-download --last --timeout 8000)"
nav_completed="$(assert_download_completed "$response")"
log "navigate download completed: $nav_completed"

response="$(run_cli downloads)"
assert_ok_json "$response"
python3 - "$response" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
result = payload.get("result", {})
downloads = result.get("downloads", [])
if len([d for d in downloads if d.get("state") == "completed"]) < 2:
    raise SystemExit(f"expected at least two completed downloads: {payload}")
PY
log "verified downloads list reports completed downloads"

if [[ -n "$DOWNLOAD_SERVER_PID" ]] && kill -0 "$DOWNLOAD_SERVER_PID" 2>/dev/null; then
  kill "$DOWNLOAD_SERVER_PID" 2>/dev/null || true
  wait "$DOWNLOAD_SERVER_PID" 2>/dev/null || true
  DOWNLOAD_SERVER_PID=""
fi
log "verifying session-snapshot artifact"
SESSION_SNAP="$SMOKE_DIR/session.json"
response="$(run_cli session-snapshot "$SESSION_SNAP")"
assert_ok_json "$response"
assert_result_field "$response" "path" "$SESSION_SNAP"
python3 - "$SESSION_SNAP" <<'PY'
import json, sys
artifact = json.load(open(sys.argv[1]))
# Schema version
if artifact.get("schemaVersion") != 1:
    raise SystemExit(f"expected schemaVersion=1: {artifact}")
# Required top-level fields
for field in ("sessionId", "profile", "persistent", "dataStore", "activeTabId", "viewport", "tabs"):
    if field not in artifact:
        raise SystemExit(f"missing field {field!r} in snapshot: {artifact}")
# Viewport shape
vp = artifact["viewport"]
if "width" not in vp or "height" not in vp:
    raise SystemExit(f"missing viewport dimensions: {vp}")
# Tabs
tabs = artifact["tabs"]
if len(tabs) < 2:
    raise SystemExit(f"expected >=2 tabs in snapshot; got {len(tabs)}")
active_tabs = [t for t in tabs if t.get("active")]
if len(active_tabs) != 1:
    raise SystemExit(f"expected exactly one active tab; got {active_tabs}")
if active_tabs[0]["id"] != artifact["activeTabId"]:
    raise SystemExit(f"activeTabId mismatch: {artifact['activeTabId']!r} vs tab.id {active_tabs[0]['id']!r}")
# Every tab has required fields
for tab in tabs:
    for field in ("id", "active", "url", "title", "loading", "networkCapturing", "consoleCapturing"):
        if field not in tab:
            raise SystemExit(f"tab {tab.get('id')!r} missing field {field!r}: {tab}")
print(f"session-snapshot ok: {len(tabs)} tabs, activeTabId={artifact['activeTabId']!r}, viewport={vp['width']}x{vp['height']}")
PY
log "verified session-snapshot artifact"


log "ok"
log "artifacts: $SMOKE_DIR"

