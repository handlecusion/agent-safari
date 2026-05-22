# CI/CD

agent-safari uses GitHub Actions for three separate lanes: fast pull-request validation, real macOS smoke testing, and release publishing.

## 1. CI: `.github/workflows/ci.yml`

Runs on every push to `main` and every pull request targeting `main`.

Checks:

- Swift unit tests: `swift test`
- Release build compilation: `swift build -c release`
- Python MCP wrapper syntax: `python3 -m py_compile ...`
- Shell script syntax: `bash -n scripts/*.sh`
- Public release audit tests: `python3 Tests/test_public_release_audit.py`
- Public release hygiene audit: `python3 scripts/public_release_audit.py`

This lane intentionally avoids real GUI daemon automation so normal PR checks stay stable and fast.

## 2. macOS Smoke: `.github/workflows/smoke.yml`

Runs manually with `workflow_dispatch` and weekly on Monday.

Checks:

- Builds the debug CLI.
- Starts the real WebKit daemon on a Unix socket.
- Runs `scripts/smoke_cli.sh` against a local fixture.
- Runs `scripts/smoke_mcp_wrapper.py` against a running daemon.
- Uploads `.tmp` artifacts if the smoke test fails.

This lane validates the behavior that unit tests cannot fully cover: WKWebView lifecycle, DOM refs, native click, full-page screenshot, network instrumentation, and MCP wrapper CLI bridging.

## 3. Release/CD: `.github/workflows/release.yml`

Runs on tags matching `v*` and can also be started manually.

Release gate:

- Runs the same core checks as CI.
- Builds the release binary with `swift build -c release`.
- Packages the CLI, MCP wrapper, install helper, README, and LICENSE with `scripts/package_release.sh`.
- Uploads the zip and SHA-256 checksums as a workflow artifact.
- Publishes or updates the GitHub Release with the packaged artifacts.

Tag release example:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Manual prerelease example:

1. Open GitHub Actions.
2. Select `Release`.
3. Run workflow with `version` like `v0.1.0-rc.1` and `prerelease=true`.

## Recommended repository settings

For public readiness, configure branch protection on `main`:

- Require pull request before merging.
- Require status checks to pass before merging.
- Required check: `Unit, syntax, and public-readiness checks`.
- Require branches to be up to date before merging.
- Restrict force pushes and deletions.

Also configure release controls:

- Protect `v*` tags so only maintainers can create release tags.
- Configure the `release` GitHub Environment with reviewer approval before public publishing if the repository has multiple write-capable collaborators.

Keep `macOS Smoke` as manual/weekly until it proves stable on hosted macOS runners. After it is stable, it can become a required check for release branches or tags.
