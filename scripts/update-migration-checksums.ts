#!/usr/bin/env tsx
/**
 * Regenerates `supabase/migrations/_checksums.sha256` from current migration files.
 *
 * Run this AFTER adding a new migration file and BEFORE opening a PR:
 *   npm run checksums:update
 *
 * CI then verifies that previously-merged migrations were not edited by
 * running `sha256sum -c _checksums.sha256` in `supabase/migrations/`.
 */

import { execSync } from 'node:child_process';
import { readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const MIG_DIR = 'supabase/migrations';
const OUT = join(MIG_DIR, '_checksums.sha256');

const files = readdirSync(MIG_DIR)
  .filter((f) => f.endsWith('.sql'))
  .sort();

if (files.length === 0) {
  process.stderr.write('no migrations found\n');
  process.exit(1);
}

// macOS uses `shasum -a 256`; Linux uses `sha256sum`. Output format is identical.
const cmd = process.platform === 'darwin' ? 'shasum -a 256' : 'sha256sum';

const lines: string[] = [];
for (const f of files) {
  const out = execSync(`${cmd} ${f}`, { cwd: MIG_DIR, encoding: 'utf8' });
  lines.push(out.trim());
}

writeFileSync(OUT, `${lines.join('\n')}\n`);
process.stdout.write(`${files.length} checksums written to ${OUT}\n`);
