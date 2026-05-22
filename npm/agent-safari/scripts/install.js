#!/usr/bin/env node
'use strict';

const fs = require('fs');
const https = require('https');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const packageRoot = path.resolve(__dirname, '..');
const packageJson = require(path.join(packageRoot, 'package.json'));
const owner = process.env.AGENT_SAFARI_GITHUB_OWNER || 'handlecusion';
const repo = process.env.AGENT_SAFARI_GITHUB_REPO || 'agent-safari';
const version = process.env.AGENT_SAFARI_VERSION || `v${packageJson.version}`;

function log(message) {
  console.log(`[agent-safari npm] ${message}`);
}

function fail(message) {
  console.error(`[agent-safari npm] ${message}`);
  process.exit(1);
}

function assetSuffix() {
  if (process.platform !== 'darwin') {
    fail(`unsupported platform: ${process.platform}; agent-safari currently requires macOS`);
  }
  if (process.arch === 'arm64') return 'macOS-ARM64';
  if (process.arch === 'x64') return 'macOS-X64';
  fail(`unsupported architecture: ${process.arch}`);
}

function download(url, destination, redirects = 0) {
  if (redirects > 5) fail(`too many redirects while downloading ${url}`);
  return new Promise((resolve, reject) => {
    const request = https.get(url, { headers: { 'User-Agent': 'agent-safari-npm-installer' } }, (response) => {
      if ([301, 302, 303, 307, 308].includes(response.statusCode || 0)) {
        response.resume();
        const location = response.headers.location;
        if (!location) return reject(new Error(`redirect without Location from ${url}`));
        return resolve(download(new URL(location, url).toString(), destination, redirects + 1));
      }
      if (response.statusCode !== 200) {
        response.resume();
        return reject(new Error(`download failed ${response.statusCode}: ${url}`));
      }
      const file = fs.createWriteStream(destination);
      response.pipe(file);
      file.on('finish', () => file.close(resolve));
      file.on('error', reject);
    });
    request.on('error', reject);
  });
}

async function main() {
  if (process.env.AGENT_SAFARI_SKIP_DOWNLOAD === '1') {
    log('AGENT_SAFARI_SKIP_DOWNLOAD=1; skipping binary download');
    return;
  }

  if (!/^v\d+\.\d+\.\d+(-[A-Za-z0-9][A-Za-z0-9.-]*)?$/.test(version)) {
    log(`package version ${version} is not a release tag; skipping binary download`);
    return;
  }

  const suffix = assetSuffix();
  const assetName = `agent-safari-${version}-${suffix}.zip`;
  const url = `https://github.com/${owner}/${repo}/releases/download/${version}/${assetName}`;
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-safari-npm-'));
  const zipPath = path.join(tmpDir, assetName);
  const extractDir = path.join(tmpDir, 'extract');
  const vendorDir = path.join(packageRoot, 'vendor');

  log(`downloading ${url}`);
  await download(url, zipPath);
  fs.mkdirSync(extractDir, { recursive: true });

  const unzip = spawnSync('ditto', ['-x', '-k', zipPath, extractDir], { stdio: 'inherit' });
  if (unzip.status !== 0) fail('failed to unzip release asset with ditto');

  const stagedRoot = path.join(extractDir, assetName.replace(/\.zip$/, ''));
  const binary = path.join(stagedRoot, 'bin', 'agent-safari');
  if (!fs.existsSync(binary)) fail(`release asset did not contain bin/agent-safari: ${assetName}`);

  fs.rmSync(vendorDir, { recursive: true, force: true });
  fs.mkdirSync(path.join(vendorDir, 'bin'), { recursive: true });
  fs.copyFileSync(binary, path.join(vendorDir, 'bin', 'agent-safari'));
  fs.chmodSync(path.join(vendorDir, 'bin', 'agent-safari'), 0o755);
  fs.rmSync(tmpDir, { recursive: true, force: true });
  log('installed vendor/bin/agent-safari');
}

main().catch((error) => fail(error.message));
