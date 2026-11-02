#!/usr/bin/env node
'use strict';

// node hooks.js <status|install|uninstall> <claude|codex|agy>  ->  {"ok":true,"data":{...}} | {"ok":false,"error":"..."}
const installers = { claude: require('./scripts/install-hooks'), codex: require('./scripts/install-codex-hooks'), agy: require('./scripts/install-hooks-agy') };

const [action, target] = process.argv.slice(2);
const installer = installers[target];
try {
  if (!installer || !['status', 'install', 'uninstall'].includes(action)) throw new Error('usage: hooks.js <status|install|uninstall> <claude|codex|agy>');
  process.stdout.write(JSON.stringify({ ok: true, data: installer[action]() }) + '\n');
} catch (err) {
  process.stdout.write(JSON.stringify({ ok: false, error: err.message }) + '\n');
  process.exitCode = 1;
}
