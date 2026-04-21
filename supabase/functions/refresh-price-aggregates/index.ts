// Edge Function: refresh-price-aggregates
//
// Calls the `refresh_price_aggregates_daily()` RPC shipped by init_core.
// Intended to be triggered by external cron (cron-job.org, scheduled
// GitHub Actions, or Supabase cron when available on the current plan).
//
// Invocation:
//   POST https://<project>.functions.supabase.co/refresh-price-aggregates
//   Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY env vars.');
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const started = Date.now();
  const { error } = await supabase.rpc('refresh_price_aggregates_daily');

  if (error) {
    return new Response(
      JSON.stringify({ ok: false, error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  return new Response(
    JSON.stringify({ ok: true, elapsed_ms: Date.now() - started }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
