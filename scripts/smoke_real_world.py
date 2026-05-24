#!/usr/bin/env python3
"""Run five real WebKit smoke scenarios and generate a screenshot report.

This is the regression suite for agent-safari's practical browser automation
contract: snapshot refs, form actions, screenshots, fetch/XHR + resource-timing
network export, tabs/session/profile state, and native no-fallback click.
"""
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import os
import shutil
import struct
import subprocess
import sys
import textwrap
import time
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from threading import Thread
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / '.build' / 'debug' / 'agent-safari'
RUN_ID = dt.datetime.now().strftime('%Y%m%d-%H%M%S')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Run five real WebKit smoke scenarios and generate a screenshot report.'
    )
    parser.add_argument(
        '--out-dir',
        default=os.environ.get('AGENT_SAFARI_SMOKE_DIR') or os.environ.get('AGENT_SAFARI_SMOKE_OUT'),
        help='Artifact directory. Defaults to .tmp/agent-safari-5-scenarios-<timestamp>. '
             'Can also be set with AGENT_SAFARI_SMOKE_DIR.',
    )
    parser.add_argument(
        '--socket',
        default=os.environ.get('AGENT_SAFARI_SOCKET'),
        help='Unix socket path for the temporary daemon. Defaults to <out-dir>/agent-safari.sock.',
    )
    parser.add_argument(
        '--skip-build',
        action='store_true',
        help='Skip swift build/test preflight when the binary and tests were already verified.',
    )
    return parser.parse_args()


ARGS = parse_args()
OUT = Path(ARGS.out_dir).expanduser().resolve() if ARGS.out_dir else ROOT / '.tmp' / f'agent-safari-5-scenarios-{RUN_ID}'
FIX = OUT / 'fixtures'
CAP = OUT / 'captures'
DATA = OUT / 'data'
SOCKET = Path(ARGS.socket).expanduser().resolve() if ARGS.socket else OUT / 'agent-safari.sock'
LOG = OUT / 'daemon.log'

SCENARIOS: list[dict] = []
STRICT_NATIVE = os.environ.get('AGENT_SAFARI_STRICT_NATIVE') == '1'


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(content).strip() + '\n', encoding='utf-8')


def json_dump(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding='utf-8')


def run_cli(*args: str, timeout: int = 20, check: bool = True):
    cmd = [str(BIN), *args, '--socket', str(SOCKET)]
    p = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, timeout=timeout)
    record = {
        'cmd': cmd,
        'returncode': p.returncode,
        'stdout': p.stdout.strip(),
        'stderr': p.stderr.strip(),
    }
    if check and p.returncode != 0:
        raise RuntimeError(f"command failed: {' '.join(cmd)}\nstdout={p.stdout}\nstderr={p.stderr}")
    try:
        record['json'] = json.loads(p.stdout) if p.stdout.strip() else None
    except json.JSONDecodeError:
        record['json_error'] = True
    if check and isinstance(record.get('json'), dict) and record['json'].get('ok') is False:
        raise RuntimeError(f"command returned ok=false: {' '.join(cmd)}\nstdout={p.stdout}\nstderr={p.stderr}")
    return record


def result_payload(record):
    parsed = record.get('json') or {}
    return parsed.get('result') or {}


def png_dimensions(path: Path) -> tuple[int, int]:
    header = path.read_bytes()[:24]
    if len(header) < 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise AssertionError(f'not a PNG screenshot artifact: {path}')
    return struct.unpack('>II', header[16:24])


def screenshot_artifact(path: Path | str, min_width: int = 1, min_height: int = 1) -> dict:
    image = Path(path)
    if not image.exists() or image.stat().st_size <= 0:
        raise AssertionError(f'screenshot artifact missing or empty: {image}')
    width, height = png_dimensions(image)
    if width < min_width or height < min_height:
        raise AssertionError(
            f'screenshot artifact has implausible dimensions: {image} {width}x{height} '
            f'(expected >= {min_width}x{min_height})'
        )
    return {'path': str(image), 'bytes': image.stat().st_size, 'width': width, 'height': height}


def assert_full_page_taller_than_viewport(full_path: Path | str, viewport_path: Path | str) -> dict:
    full = screenshot_artifact(full_path, min_width=100, min_height=100)
    viewport = screenshot_artifact(viewport_path, min_width=100, min_height=100)
    if full['height'] <= viewport['height']:
        raise AssertionError(f'full-page screenshot is not taller than viewport: full={full} viewport={viewport}')
    return {'full': full, 'viewport': viewport}


def _bool_metadata(value) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered == 'true':
            return True
        if lowered == 'false':
            return False
    raise AssertionError(f'expected boolean metadata string, got {value!r}')


def native_click_delivery(payload: dict, strict_native: bool) -> dict:
    missing = [key for key in ('method', 'nativeVerified', 'fallbackUsed') if key not in payload]
    if missing:
        raise AssertionError(f'missing native click metadata: {missing}; payload={payload}')
    method = str(payload['method'])
    native_verified = _bool_metadata(payload['nativeVerified'])
    fallback_used = _bool_metadata(payload['fallbackUsed'])
    acceptable = method == 'native' and native_verified and not fallback_used
    if not strict_native:
        acceptable = acceptable or (method == 'dom-fallback' and not native_verified and fallback_used)
    return {
        'method': method,
        'nativeVerified': native_verified,
        'fallbackUsed': fallback_used,
        'acceptable': acceptable,
    }


def snapshot_elements(record) -> list[dict]:
    payload = result_payload(record)
    raw = payload.get('snapshot')
    if isinstance(raw, str):
        return json.loads(raw)
    if isinstance(raw, list):
        return raw
    if isinstance(payload.get('elements'), list):
        return payload['elements']
    return []


def file_url(path: Path) -> str:
    return path.resolve().as_uri()


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get('content-length', '0') or '0')
        body = self.rfile.read(length) if length else b''
        payload = json.dumps({
            'ok': True,
            'source': 'xhr',
            'message': 'hello from xhr',
            'received': body.decode('utf-8', errors='replace'),
        }).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def start_http_server(directory: Path):
    class Handler(QuietHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(directory), **kwargs)
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, f'http://127.0.0.1:{server.server_port}'


def wait_for_daemon(deadline_sec: int = 15) -> None:
    deadline = time.time() + deadline_sec
    last = None
    while time.time() < deadline:
        try:
            rec = run_cli('status', timeout=3, check=False)
            last = rec
            if rec['returncode'] == 0 and (rec.get('json') or {}).get('ok') is True:
                return
        except Exception as e:
            last = repr(e)
        time.sleep(0.3)
    raise RuntimeError(f'daemon not ready; last={last}; log={LOG.read_text(errors="ignore") if LOG.exists() else ""}')


def screenshot(name: str, full: bool = False, selector: str | None = None):
    path = CAP / f'{name}.png'
    if selector:
        rec = run_cli('screenshot', '--element', selector, '--out', str(path), timeout=20)
    elif full:
        rec = run_cli('screenshot', '--full', '--out', str(path), timeout=30)
    else:
        rec = run_cli('screenshot', '--out', str(path), timeout=20)
    return str(path), rec


def scenario(name: str, purpose: str, steps: list, captures: list[str], evidence: dict, verdict: str):
    SCENARIOS.append({
        'name': name,
        'purpose': purpose,
        'steps': steps,
        'captures': captures,
        'evidence': evidence,
        'verdict': verdict,
    })


def make_contact_sheet() -> Path | None:
    try:
        from PIL import Image, ImageDraw
    except Exception:
        return None
    captures = sorted(CAP.glob('*.png'))
    if not captures:
        return None
    thumbs = []
    for path in captures:
        image = Image.open(path).convert('RGB')
        image.thumbnail((520, 320))
        canvas = Image.new('RGB', (560, 380), 'white')
        canvas.paste(image, ((560 - image.width) // 2, 20))
        draw = ImageDraw.Draw(canvas)
        draw.text((16, 340), path.name, fill=(20, 30, 45))
        thumbs.append(canvas)
    cols = 2
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * 560, rows * 380), (245, 247, 250))
    for index, thumb in enumerate(thumbs):
        sheet.paste(thumb, ((index % cols) * 560, (index // cols) * 380))
    out = CAP / '00_contact_sheet.png'
    sheet.save(out)
    return out


def make_fixtures(base_url: str):
    write(FIX / 'index.html', f'''
    <!doctype html><html><head><meta charset="utf-8"><title>Agent Safari Form Scenario</title>
    <style>
      body {{ font: 16px -apple-system, BlinkMacSystemFont, sans-serif; margin: 32px; background: #f7f8fb; color: #172033; }}
      .card {{ max-width: 780px; padding: 24px; background:white; border-radius:18px; box-shadow:0 12px 30px #0001; }}
      label {{ display:block; margin:14px 0 6px; font-weight:700; }}
      input, textarea {{ width:100%; padding:12px; border:1px solid #ccd4e0; border-radius:10px; font-size:16px; }}
      button {{ margin-top:18px; padding:12px 18px; border:0; border-radius:12px; background:#0b5fff; color:white; font-weight:800; }}
      #result {{ margin-top:20px; padding:14px; background:#eef6ff; border-radius:12px; min-height:24px; }}
      .badge {{ display:inline-block; padding:4px 9px; border-radius:999px; background:#e5edff; color:#174ea6; font-size:13px; }}
    </style></head><body>
      <main class="card">
        <span class="badge">Scenario 1</span>
        <h1>Snapshot refs + fill/click</h1>
        <p>이 페이지는 snapshot의 @e ref, fill, click, element screenshot을 검증합니다.</p>
        <label for="name">이름</label><input id="name" name="name" placeholder="이름 입력">
        <label for="memo">메모</label><textarea id="memo" name="memo" placeholder="메모 입력"></textarea>
        <button id="submit" onclick="document.getElementById('result').textContent='제출 완료: '+document.getElementById('name').value+' / '+document.getElementById('memo').value">제출</button>
        <div id="result" role="status">대기 중</div>
      </main>
    </body></html>
    ''')

    rows = '\n'.join(f'<section><h2>Long section {i}</h2><p>Full-page screenshot tile row {i}. agent-safari should preserve the tall page content and restore scrolling.</p></section>' for i in range(1, 31))
    write(FIX / 'long.html', f'''
    <!doctype html><html><head><meta charset="utf-8"><title>Agent Safari Full Page Scenario</title>
    <style>body{{font:17px -apple-system;margin:0;background:linear-gradient(#eef4ff,#fff7ec)}} header{{position:sticky;top:0;background:#172033;color:white;padding:20px 32px;z-index:2}} section{{margin:28px auto;padding:28px;max-width:850px;background:white;border-radius:18px;box-shadow:0 8px 24px #0001}} h2{{color:#0b5fff}}</style></head>
    <body><header><h1>Scenario 2: Tall full-page screenshot</h1></header>{rows}<footer style="padding:40px;text-align:center">END-OF-LONG-PAGE</footer></body></html>
    ''')

    write(FIX / 'network.json', '{"ok":true,"source":"fetch","message":"hello from fixture"}')
    write(FIX / 'xhr.json', '{"ok":true,"source":"xhr","message":"hello from xhr"}')
    write(FIX / 'style.css', 'body::after{content:"";display:block;width:1px;height:1px;background:#0b5fff}')
    write(FIX / 'pixel.svg', '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12"><rect width="12" height="12" fill="#0b5fff"/></svg>')
    write(FIX / 'network.html', f'''
    <!doctype html><html><head><meta charset="utf-8"><title>Agent Safari Network Scenario</title>
    <link rel="stylesheet" href="/style.css">
    <style>body{{font:16px -apple-system;margin:32px}} button{{padding:12px 18px;border-radius:12px;border:0;background:#111827;color:white}} pre{{background:#f3f4f6;padding:16px;border-radius:12px}}</style></head>
    <body><h1>Scenario 3: fetch/XHR capture</h1><img alt="resource timing probe" src="/pixel.svg"><button id="load">Load network data</button><pre id="out">waiting</pre>
    <script>
      document.getElementById('load').onclick = async () => {{
        const f = await fetch('/network.json', {{headers: {{'X-Demo': 'agent-safari'}}}}).then(r => r.json());
        const x = await new Promise((resolve) => {{ const xhr = new XMLHttpRequest(); xhr.open('POST', '/xhr.json'); xhr.setRequestHeader('Content-Type','application/json'); xhr.onload=()=>resolve(JSON.parse(xhr.responseText)); xhr.send(JSON.stringify({{hello:'world'}})); }});
        document.getElementById('out').textContent = JSON.stringify({{fetch:f, xhr:x}}, null, 2);
      }};
    </script></body></html>
    ''')

    write(FIX / 'tab-a.html', '''
    <!doctype html><html><head><meta charset="utf-8"><title>Tab A</title><style>body{font:20px -apple-system;margin:40px;background:#ecfeff}</style></head><body><h1>Scenario 4: Tab A</h1><p id="marker">TAB_A_MARKER</p></body></html>
    ''')
    write(FIX / 'tab-b.html', '''
    <!doctype html><html><head><meta charset="utf-8"><title>Tab B</title><style>body{font:20px -apple-system;margin:40px;background:#fef3c7}</style></head><body><h1>Scenario 4: Tab B</h1><p id="marker">TAB_B_MARKER</p></body></html>
    ''')

    write(FIX / 'native.html', '''
    <!doctype html><html><head><meta charset="utf-8"><title>Agent Safari Native Input Scenario</title>
    <style>body{font:17px -apple-system;margin:32px;background:#fbfbff}.wrap{max-width:760px;background:white;padding:24px;border-radius:18px;box-shadow:0 12px 30px #0001}button{padding:12px 18px;border:0;border-radius:12px;background:#16a34a;color:white;font-weight:800}input{padding:12px;border:1px solid #ccd4e0;border-radius:10px;width:280px}</style></head>
    <body><div class="wrap"><h1>Scenario 5: Native click + type/viewport</h1><p>Native Quartz click with JS fallback verification and synthetic typing.</p><input id="typed" placeholder="type here"><button id="nativeBtn">Native target</button><div id="state">initial</div></div>
    <script>
      document.getElementById('nativeBtn').addEventListener('click', () => { document.getElementById('state').textContent = 'native click observed'; });
    </script></body></html>
    ''')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    CAP.mkdir(parents=True, exist_ok=True)
    DATA.mkdir(parents=True, exist_ok=True)
    if not ARGS.skip_build:
        subprocess.run(['swift', 'build'], cwd=ROOT, check=True)
        subprocess.run(['swift', 'test'], cwd=ROOT, check=True)

    # Create fixtures after knowing HTTP base.
    server, base = start_http_server(FIX)
    make_fixtures(base)

    daemon = subprocess.Popen([str(BIN), 'daemon', '--profile', f'scenario-{RUN_ID}', '--ephemeral', '--socket', str(SOCKET)], cwd=ROOT, stdout=LOG.open('w'), stderr=subprocess.STDOUT, text=True)
    try:
        wait_for_daemon()

        # Scenario 1: snapshot refs + form fill/click + element screenshot.
        steps = []
        steps.append(run_cli('open', file_url(FIX / 'index.html')))
        steps.append(run_cli('wait-for-text', '대기 중', '--timeout', '5000'))
        snap = run_cli('snapshot')
        elements = snapshot_elements(snap)
        name_ref = next((e['ref'] for e in elements if e.get('tag') == 'input' and (e.get('selector') == 'input#name' or e.get('accessibleName') == '이름')), None)
        memo_ref = next((e['ref'] for e in elements if e.get('tag') == 'textarea' and (e.get('selector') == 'textarea#memo' or e.get('accessibleName') == '메모')), None)
        submit_ref = next((e['ref'] for e in elements if e.get('tag') == 'button' and (e.get('selector') == 'button#submit' or e.get('accessibleName') == '제출')), None)
        if not all([name_ref, memo_ref, submit_ref]) or not all(str(ref).startswith('@e') for ref in [name_ref, memo_ref, submit_ref]):
            raise RuntimeError(f'failed to resolve @e snapshot refs: name={name_ref} memo={memo_ref} submit={submit_ref} elements={elements}')
        steps.append(snap)
        steps.append(run_cli('fill', str(name_ref), '현윤성'))
        steps.append(run_cli('fill', str(memo_ref), 'agent-safari 5 scenario smoke'))
        steps.append(run_cli('click', str(submit_ref)))
        steps.append(run_cli('wait-for-text', '제출 완료', '--timeout', '5000'))
        cap1, _ = screenshot('01_form_after_submit')
        cap1e, _ = screenshot('01_result_element', selector='#result')
        cap1_artifact = screenshot_artifact(cap1, min_width=100, min_height=100)
        cap1e_artifact = screenshot_artifact(cap1e, min_width=20, min_height=20)
        eval1 = run_cli('evaluate', "document.getElementById('result').textContent")
        scenario('1. Snapshot refs + form action', 'snapshot @e refs로 input/textarea/button을 찾아 fill/click 후 상태 영역을 element screenshot으로 검증', steps, [cap1, cap1e], {'refs': {'name': name_ref, 'memo': memo_ref, 'submit': submit_ref}, 'resultText': result_payload(eval1).get('value'), 'screenshots': [cap1_artifact, cap1e_artifact]}, 'PASS' if '제출 완료: 현윤성 / agent-safari 5 scenario smoke' in str(result_payload(eval1)) else 'CHECK')

        # Scenario 2: full page screenshot.
        steps = [run_cli('open', file_url(FIX / 'long.html')), run_cli('wait-for-text', 'END-OF-LONG-PAGE', '--timeout', '5000')]
        cap2, _ = screenshot('02_long_full_page', full=True)
        cap2v, _ = screenshot('02_long_viewport')
        screenshot_comparison = assert_full_page_taller_than_viewport(cap2, cap2v)
        info2 = run_cli('evaluate', 'JSON.stringify({height: document.documentElement.scrollHeight, viewport: innerHeight, title: document.title})')
        scenario('2. Tall page full screenshot', '긴 페이지에서 full-page capture와 viewport capture를 비교해 tiled screenshot 경로를 검증', steps, [cap2, cap2v], {'pageInfo': result_payload(info2).get('value'), 'screenshots': screenshot_comparison}, 'PASS' if screenshot_comparison['full']['height'] > screenshot_comparison['viewport']['height'] else 'CHECK')

        # Scenario 3: fetch/XHR network export.
        steps = [run_cli('open', base + '/network.html'), run_cli('network', 'start'), run_cli('click', '#load'), run_cli('wait-for-text', 'hello from xhr', '--timeout', '5000')]
        net_list = run_cli('network', 'list')
        net_export_path = DATA / '03_network.har.json'
        net_export = run_cli('network', 'export', str(net_export_path), '--body-preview-bytes', '80', '--max-entries', '20')
        har = json.loads(net_export_path.read_text(encoding='utf-8'))
        resource_timing_count = har.get('agentSafari', {}).get('resourceTimingCount', 0)
        cap3, _ = screenshot('03_network_after_load')
        cap3_artifact = screenshot_artifact(cap3, min_width=100, min_height=100)
        events = result_payload(net_list).get('events', [])
        scenario('3. Fetch/XHR + resource timing network capture', 'JS fetch/XHR instrumentation과 PerformanceResourceTiming 기반 parser-driven resource export를 검증', steps + [net_list, net_export], [cap3], {'eventCount': len(events), 'types': [e.get('type') for e in events], 'resourceTimingCount': resource_timing_count, 'export': str(net_export_path), 'screenshot': cap3_artifact}, 'PASS' if len(events) >= 2 and resource_timing_count >= 1 else 'CHECK')

        # Scenario 4: true tab/session/profile behavior.
        steps = [run_cli('open', file_url(FIX / 'tab-a.html'))]
        tab_new = run_cli('tab-new', file_url(FIX / 'tab-b.html'))
        tab_b = result_payload(tab_new).get('id') or result_payload(tab_new).get('tabId')
        tabs_after_new = run_cli('tabs')
        session_after_new = run_cli('session')
        steps.extend([tab_new, tabs_after_new, session_after_new])
        cap4b, _ = screenshot('04_tab_b_active')
        cap4b_artifact = screenshot_artifact(cap4b, min_width=100, min_height=100)
        steps.append(run_cli('tab-switch', 'tab-1'))
        cap4a, _ = screenshot('04_tab_a_restored')
        cap4a_artifact = screenshot_artifact(cap4a, min_width=100, min_height=100)
        tabs_after_switch = run_cli('tabs')
        scenario('4. Multi-tab/session/profile', 'ephemeral profile daemon에서 tab-new/tab-switch/session/tab count를 검증', steps + [tabs_after_switch], [cap4b, cap4a], {'newTabId': tab_b, 'session': result_payload(session_after_new), 'tabs': result_payload(tabs_after_switch), 'screenshots': [cap4b_artifact, cap4a_artifact]}, 'PASS' if str(result_payload(session_after_new).get('tabCount')) == '2' else 'CHECK')

        # Scenario 5: native click, type, viewport, observe.
        steps = [run_cli('viewport', '900', '640'), run_cli('open', file_url(FIX / 'native.html')), run_cli('wait-for-selector', '#nativeBtn', '--timeout', '5000')]
        before = run_cli('observe')
        native_args = ('click', '#nativeBtn', '--native', '--no-fallback') if STRICT_NATIVE else ('click', '#nativeBtn', '--native')
        native_click = run_cli(*native_args)
        steps.append(native_click)
        steps.append(run_cli('wait-for-text', 'native click observed', '--timeout', '5000'))
        steps.append(run_cli('click', '#typed'))
        steps.append(run_cli('type', 'typed by agent-safari'))
        after = run_cli('observe')
        cap5, _ = screenshot('05_native_click_and_type')
        cap5_artifact = screenshot_artifact(cap5, min_width=100, min_height=100)
        eval5 = run_cli('evaluate', "JSON.stringify({state:document.getElementById('state').textContent, typed:document.getElementById('typed').value, w:innerWidth, h:innerHeight})")
        native_payload = result_payload(native_click)
        native_delivery = native_click_delivery(native_payload, strict_native=STRICT_NATIVE)
        scenario('5. Native click + synthetic type + viewport', 'native click을 우선 시도하고 기본 smoke에서는 JS fallback까지, AGENT_SAFARI_STRICT_NATIVE=1에서는 no-fallback native-only를 검증', steps + [before, after, eval5], [cap5], {'strictNative': STRICT_NATIVE, 'nativeClick': native_payload, 'nativeDelivery': native_delivery, 'pageState': result_payload(eval5).get('value'), 'observeAfter': result_payload(after), 'screenshot': cap5_artifact}, 'PASS' if native_delivery['acceptable'] and 'native click observed' in str(result_payload(eval5)) and 'typed by agent-safari' in str(result_payload(eval5)) else 'CHECK')

        json_dump(DATA / 'scenario-results.json', SCENARIOS)
        make_contact_sheet()
        make_report()
        failures = [s for s in SCENARIOS if s['verdict'] != 'PASS']
        if failures:
            raise RuntimeError('smoke scenarios did not all pass: ' + ', '.join(s['name'] for s in failures))
    finally:
        server.shutdown()
        if daemon.poll() is None:
            daemon.terminate()
            try:
                daemon.wait(timeout=5)
            except subprocess.TimeoutExpired:
                daemon.kill()
        try:
            SOCKET.unlink()
        except FileNotFoundError:
            pass

    print(f'report={OUT / "REPORT.md"}')
    print(f'artifacts={OUT}')


def make_report():
    passed = sum(1 for s in SCENARIOS if s['verdict'] == 'PASS')
    lines = []
    lines.append(f'# agent-safari 5-scenario screenshot report')
    lines.append('')
    lines.append(f'- run id: `{RUN_ID}`')
    lines.append(f'- repo: `{ROOT}`')
    lines.append(f'- artifacts: `{OUT}`')
    lines.append(f'- result: {passed}/{len(SCENARIOS)} PASS')
    lines.append(f'- scope: priority 1~3 validation — doctor-like status/session, smoke-quality WebKit scenarios, snapshots/input/screenshots/network/tabs/profile')
    lines.append('')
    lines.append('## Executive summary')
    lines.append('')
    contact_sheet = CAP / '00_contact_sheet.png'
    if contact_sheet.exists():
        lines.append(f'- contact sheet: `{contact_sheet}`')
        lines.append('  ![](captures/00_contact_sheet.png)')
        lines.append('')
    for s in SCENARIOS:
        lines.append(f"- {s['verdict']}: {s['name']} — {s['purpose']}")
    lines.append('')
    lines.append('## Scenario details')
    for i, s in enumerate(SCENARIOS, 1):
        lines.append('')
        lines.append(f"### {s['name']}")
        lines.append('')
        lines.append(f"- verdict: **{s['verdict']}**")
        lines.append(f"- purpose: {s['purpose']}")
        lines.append('- evidence:')
        for key, value in s['evidence'].items():
            pretty = json.dumps(value, ensure_ascii=False) if isinstance(value, (dict, list)) else str(value)
            lines.append(f"  - {key}: `{pretty[:1000]}`")
        lines.append('- captures:')
        for cap in s['captures']:
            rel = Path(cap).relative_to(OUT)
            lines.append(f"  - `{cap}`")
            lines.append(f"    ![]({rel.as_posix()})")
    lines.append('')
    lines.append('## Notes / gaps found')
    lines.append('')
    lines.append('- Network export now includes fetch/XHR entries plus parser-driven resource timing entries. Resource timing entries do not include request/response headers or body data.')
    lines.append('- Native click reports the selected strategy plus explicit `method`, `nativeVerified`, and `fallbackUsed` metadata. Default smoke permits JS fallback after a native miss; set `AGENT_SAFARI_STRICT_NATIVE=1` to make native-only delivery a hard gate.')
    lines.append('- In the current local session strict native delivery is still environment-sensitive; fallback evidence is explicit in `nativeClick.method`, `nativeClick.fallbackUsed`, and `nativeClick.nativeError`.')
    lines.append('- The tab scenario uses actual WKWebView tab model on current HEAD; this is stronger than the older wiki limitation that described placeholders only.')
    lines.append('- This report is a smoke evidence bundle, not a full browser conformance suite.')
    (OUT / 'REPORT.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
