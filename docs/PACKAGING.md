# Packaging and distribution

agent-safari can be distributed three ways:

1. GitHub Release zip for direct download.
2. npm package for `npx agent-safari ...` usage.
3. Homebrew formula for `brew install ...` usage.

## npm

Package source lives in `npm/agent-safari`.

The npm package is a lightweight macOS-only wrapper:

- `bin/agent-safari.js` forwards CLI arguments to the native binary.
- `scripts/install.js` downloads the matching GitHub Release zip during `postinstall`.
- `scripts/package_npm.sh` copies the npm package to `.tmp/npm-package`, rewrites the package version from `AGENT_SAFARI_VERSION`, and runs `npm pack`.

Local package smoke:

```sh
AGENT_SAFARI_VERSION=v0.1.0 scripts/package_npm.sh
AGENT_SAFARI_SKIP_DOWNLOAD=1 npm --prefix npm/agent-safari run smoke
```

Publish automation:

- `.github/workflows/publish-packages.yml` runs after a GitHub Release is published.
- If the `NPM_TOKEN` repository secret is configured, it publishes `.tmp/npm-package` to npm with `--access public`.
- If `NPM_TOKEN` is not configured, the workflow skips npm publishing but still uploads the npm tarball as an artifact.

Expected npm install experience after publishing:

```sh
npm install -g agent-safari
agent-safari daemon --socket /tmp/agent-safari.sock
```

or:

```sh
npx agent-safari status
```

## Homebrew

Formula template lives at:

```text
packaging/homebrew/Formula/agent-safari.rb.template
```

Render a formula for a release tag:

```sh
curl -fsSL https://github.com/handlecusion/agent-safari/archive/refs/tags/v0.1.0.tar.gz -o /tmp/agent-safari-v0.1.0.tar.gz
sha256="$(shasum -a 256 /tmp/agent-safari-v0.1.0.tar.gz | awk '{print $1}')"
python3 scripts/render_homebrew_formula.py --version v0.1.0 --sha256 "$sha256" --output /tmp/agent-safari.rb
ruby -c /tmp/agent-safari.rb
```

The formula builds from the tagged source archive with Swift and installs:

- `bin/agent-safari`
- `mcp/` under the Homebrew prefix

Tap automation:

- Configure repository variable `HOMEBREW_TAP_REPO`, for example `handlecusion/homebrew-agent-safari`.
- Configure repository secret `HOMEBREW_TAP_TOKEN` with push access to that tap repository.
- On release publish, `.github/workflows/publish-packages.yml` renders the formula and pushes it to `Formula/agent-safari.rb` in the tap.

Expected Homebrew usage after tap setup:

```sh
brew tap handlecusion/agent-safari
brew install agent-safari
```

If the tap repository is named with the conventional `homebrew-` prefix, `brew tap handlecusion/agent-safari` resolves to `github.com/handlecusion/homebrew-agent-safari`.

## Release flow

1. Create and push a release tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

2. The `Release` workflow publishes GitHub Release assets:

- macOS native binary zip
- SHA-256 checksums
- npm tarball

3. The `Publish Packages` workflow runs on the published release:

- Publishes npm if `NPM_TOKEN` exists.
- Renders and uploads the Homebrew formula artifact.
- Updates the Homebrew tap if `HOMEBREW_TAP_REPO` and `HOMEBREW_TAP_TOKEN` exist.
- Uploads generated package artifacts either way.
