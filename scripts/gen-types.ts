#!/usr/bin/env tsx
/**
 * Regenerates `types/database.ts` from the Supabase schema.
 *
 * Usage:
 *   npm run types:gen
 *
 * Requires:
 *   - Supabase CLI installed (`supabase` on PATH, or `npx supabase` fallback)
 *   - Project linked: `supabase link --project-ref <ref>` once per clone,
 *     OR local DB running: `supabase start`.
 *
 * Mode selection:
 *   SUPABASE_TYPES_MODE=linked (default) uses the linked cloud project.
 *   SUPABASE_TYPES_MODE=local uses the local `supabase start` database.
 */

import { execSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const OUT = resolve(process.cwd(), 'types/database.ts');
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
  const cmd = `${supabaseCmd()} gen types typescript --${mode}`;
  const out = execSync(cmd, { encoding: 'utf8' });
  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, out);
  process.stdout.write(`types regenerated at ${OUT} (mode=${mode})\n`);
}

main();
