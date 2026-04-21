#!/usr/bin/env tsx
/**
 * CI guard: fails if `types/database.ts` is stale relative to the schema.
 *
 * Regenerates types into a temporary file and diffs against the committed one.
 * Exits 1 with the diff on mismatch.
 */

import { execSync } from 'node:child_process';
import { readFileSync, writeFileSync, unlinkSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';

const COMMITTED = resolve(process.cwd(), 'types/database.ts');
const mode = process.env.SUPABASE_TYPES_MODE === 'local' ? 'local' : 'linked';

function supabaseCmd(): string {
  try {
    execSync('supabase --version', { stdio: 'ignore' });
    return 'supabase';
  } catch {
    return 'npx --yes supabase';
  }
}

function main(): void {
  const dir = mkdtempSync(join(tmpdir(), 'jinba-db-types-'));
  const tmpFile = join(dir, 'database.ts');
  const fresh = execSync(`${supabaseCmd()} gen types typescript --${mode}`, {
    encoding: 'utf8',
  });
  writeFileSync(tmpFile, fresh);

  const committed = readFileSync(COMMITTED, 'utf8');

  if (committed === fresh) {
    unlinkSync(tmpFile);
    process.stdout.write('types up-to-date\n');
    return;
  }

  process.stderr.write(
    [
      'types/database.ts is STALE relative to the schema.',
      'Run `npm run types:gen` and commit the result.',
      '',
      `committed: ${COMMITTED}`,
      `fresh:     ${tmpFile}`,
      '',
    ].join('\n'),
  );
  try {
    execSync(`diff -u ${COMMITTED} ${tmpFile}`, { stdio: 'inherit' });
  } catch {
    // diff exits non-zero when files differ; ignore.
  }
  process.exit(1);
}

main();
