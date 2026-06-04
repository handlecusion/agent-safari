# Release checklist

Use this checklist before tagging or publishing `agent-safari`.

## Required non-GUI gates

Run from the repository root:

```sh
swift test
swift build -c release
python3 -m py_compile mcp/agent_safari_mcp.py scripts/smoke_mcp_wrapper.py scripts/public_release_audit.py scripts/render_homebrew_formula.py scripts/smoke_real_world.py Tests/test_agentic_refs_contract.py Tests/test_input_keypath_contract.py Tests/test_browser_chrome_contract.py Tests/test_smoke_real_world.py
bash -n scripts/*.sh
python3 Tests/test_public_release_audit.py
python3 Tests/test_mcp_contract.py
python3 Tests/test_smoke_real_world.py
python3 Tests/test_input_keypath_contract.py
python3 Tests/test_browser_chrome_contract.py
python3 Tests/test_agentic_refs_contract.py
bash scripts/smoke_cli.sh
```

Expected result: every command exits 0. `scripts/smoke_cli.sh` builds the package, starts an isolated daemon/socket, exercises the normalized CLI path, then cleans up.

## Required GUI/manual gate

Run from a logged-in macOS GUI session where a WebKit window may be opened:

```sh
python3 scripts/smoke_real_world.py
```

Expected result:

- stdout prints `report=<artifact-dir>/REPORT.md` and `artifacts=<artifact-dir>`.
- `<artifact-dir>/REPORT.md` reports `5/5 PASS`.
- `<artifact-dir>/data/scenario-results.json` exists.
- screenshots exist under `<artifact-dir>/captures/` and `scenario-results.json` includes screenshot byte size and PNG dimensions.
- the tall-page scenario shows the full-page PNG height greater than the viewport PNG height.
- daemon output exists at `<artifact-dir>/daemon.log`.

Useful options:

```sh
python3 scripts/smoke_real_world.py --out-dir .tmp/release-smoke
python3 scripts/smoke_real_world.py --socket /tmp/agent-safari-release-smoke.sock
python3 scripts/smoke_real_world.py --skip-build
AGENT_SAFARI_SMOKE_DIR=.tmp/release-smoke python3 scripts/smoke_real_world.py
```

For stricter native-click verification:

```sh
AGENT_SAFARI_STRICT_NATIVE=1 python3 scripts/smoke_real_world.py
```

Strict native mode may require macOS Accessibility permission and a usable foreground GUI session. Default smoke allows a documented JavaScript fallback after a native miss and records the selected strategy plus explicit click metadata: `method`, `nativeVerified`, `fallbackUsed`, `nativeError`, and `nativeErrorCode` when fallback is used.

## v0.0.6 release criteria

Use v0.0.6 as the Phase 2 native input / agentic refs quality checkpoint. Do not tag the release until all of the following are true:

- The non-GUI gates above exit 0 on the release commit, including the agentic refs contract tests.
- The GUI smoke gate reports `5/5 PASS` from `python3 scripts/smoke_real_world.py` and records the artifact path in the release notes.
- Snapshot output keeps schema v2 metadata for agent refs, including stable DOM ordering and actionability fields.
- Click/fill paths reject stale snapshot refs, disabled targets, hidden targets, and off-viewport centers with explicit errors before native or DOM fallback input is attempted.
- Native click remains consent-first and evidence-rich: default smoke may allow documented DOM fallback, while strict native-only remains opt-in through `AGENT_SAFARI_STRICT_NATIVE=1`.
- The public-release audit passes and no tracked docs leak local absolute paths, secret-ish strings, or passkey/WebAuthn feature code.
- The local LLM Wiki graph/source/task evidence is refreshed after the release commit if code-affecting files changed.

## Packaging dry-runs

Before publishing packages:

```sh
rm -rf .tmp/dist .tmp/npm-install-dry-run
AGENT_SAFARI_VERSION=v0.0.0-test.1 scripts/package_npm.sh
AGENT_SAFARI_SKIP_DOWNLOAD=1 npm --prefix npm/agent-safari run smoke
mkdir -p .tmp/npm-install-dry-run
(
  cd .tmp/npm-install-dry-run
  npm init -y >/dev/null
  AGENT_SAFARI_SKIP_DOWNLOAD=1 npm install ../dist/agent-safari-0.0.0-test.1.tgz
  AGENT_SAFARI_BIN=/bin/echo npx agent-safari --version
)
python3 scripts/render_homebrew_formula.py \
  --version v0.0.0-test.1 \
  --sha256 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
  --output .tmp/homebrew/agent-safari.rb
ruby -c .tmp/homebrew/agent-safari.rb
```

Expected result: npm creates `.tmp/dist/agent-safari-0.0.0-test.1.tgz`, the temp-project install exits 0 without publishing or downloading a release asset, and the rendered Homebrew formula reports `Syntax OK`.

## GitHub CI gate

Check remote CI before tagging:

```sh
gh run list --branch main --limit 5
gh run view --log-failed
```

Expected result: latest `main` CI is green, or any failure is understood and fixed before release.

## Do not publish without approval

Do not run any of these without explicit release approval:

```sh
git tag -a v0.1.0 -m "v0.1.0"
git push origin main --tags
npm publish
```

Homebrew tap updates should also wait for explicit approval and verified tap credentials.
