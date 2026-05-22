#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const packageRoot = path.resolve(__dirname, '..');
const vendoredBinary = path.join(packageRoot, 'vendor', 'bin', 'agent-safari');
const overrideBinary = process.env.AGENT_SAFARI_BIN;
const binary = overrideBinary || vendoredBinary;

if (!fs.existsSync(binary)) {
  const hint = overrideBinary
    ? `AGENT_SAFARI_BIN points to a missing file: ${overrideBinary}`
    : [
        'agent-safari binary was not installed for this npm package.',
        'Reinstall from a published release, or set AGENT_SAFARI_BIN to a locally built binary.',
        'Example: AGENT_SAFARI_BIN=/path/to/.build/release/agent-safari npx agent-safari status',
      ].join('\n');
  console.error(hint);
  process.exit(127);
}

const result = spawnSync(binary, process.argv.slice(2), { stdio: 'inherit' });
if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}
process.exit(result.status === null ? 1 : result.status);
