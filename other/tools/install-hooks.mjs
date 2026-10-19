#!/usr/bin/env node
//
// Enables the checked-in Git hooks in .githooks.
//
// Run automatically by `npm install` through the "prepare" script in the root
// package.json, so cloning + `npm install` is all it takes. The hooks only
// rebuild editor.yymps (see other/tools/pack_yymps.ps1) and never block a push.

import { execFileSync } from 'node:child_process';
import { chmodSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const hook = join(repoRoot, '.githooks', 'pre-push');

try {
  execFileSync('git', ['-C', repoRoot, 'config', 'core.hooksPath', '.githooks'], { stdio: 'inherit' });
} catch {
  console.warn('install-hooks: git non disponibile o non e un repository: hooks non attivati.');
  process.exit(0);
}

// On macOS/Linux the hook file must be executable. No-op on Windows.
if (existsSync(hook)) {
  try {
    chmodSync(hook, 0o755);
  } catch {
    /* Windows: nothing to do */
  }
}

console.log('install-hooks: hook attivi (core.hooksPath = .githooks).');
console.log('              pre-push rigenera editor.yymps. Disattivare: git config --unset core.hooksPath');
