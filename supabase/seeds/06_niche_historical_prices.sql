-- =====================================================================
-- Seed: historical niche-generation price backfill
-- Created: 2026-04-29 UTC  (data-sources-strategy, overnight run 2026-04-23)
--
-- Seeds `ingested_price_points` with 12 monthly snapshots per (gen, year)
-- for the 5 niche generations we retain in the product:
--   mazda:mx-5:na, datsun:240z:s30, seat:leon:mk1,
--   volkswagen:golf:mk4, audi:a3:8p
--
-- Purpose: give the 365-day price-history chart and the calculator's
-- weighted-median window enough points to render meaningfully before
-- Apify ingest produces head-volume data.
--
-- Idempotent via ipp_upsert_key unique index
-- (source_slug, external_id, (observed_at at time zone 'UTC')::date).
--
-- This file is a SEED, not a migration — running `supabase db reset` replays
-- it. Production was populated once on 2026-04-23 via the equivalent MCP
-- `execute_sql` call.
-- =====================================================================

with base(gen_slug, year, km, base_price) as (
  values
    ('mazda:mx-5:na',       1992::smallint, 150000,  8500),
    ('mazda:mx-5:na',       1995::smallint, 140000,  9200),
    ('mazda:mx-5:na',       1997::smallint, 130000, 10500),
    ('datsun:240z:s30',     1972::smallint, 120000, 52000),
    ('datsun:240z:s30',     1973::smallint, 115000, 48000),
    ('seat:leon:mk1',       2001::smallint, 180000,  2800),
    ('seat:leon:mk1',       2003::smallint, 165000,  3400),
    ('seat:leon:mk1',       2005::smallint, 150000,  4200),
    ('volkswagen:golf:mk4', 1999::smallint, 200000,  2500),
    ('volkswagen:golf:mk4', 2001::smallint, 185000,  3100),
    ('volkswagen:golf:mk4', 2003::smallint, 170000,  3800),
    ('audi:a3:8p',          2004::smallint, 180000,  4500),
    ('audi:a3:8p',          2006::smallint, 165000,  5800),
    ('audi:a3:8p',          2008::smallint, 150000,  7200)
),
months as (
  -- 12 monthly snapshots: 2025-05-15 ... 2026-04-15
  select generate_series(
    '2025-05-15T00:00:00Z'::timestamptz,
    '2026-04-15T00:00:00Z'::timestamptz,
    interval '1 month'
  ) as observed_at
),
expanded as (
  select
    base.gen_slug,
    base.year,
    base.km,
    -- Deterministic ±2% jitter — reproducible given the same inputs.
    round(base.base_price * (1 + 0.02 * (
      (hashtext(base.gen_slug || base.year::text || months.observed_at::text) % 100) / 50.0 - 1
    )))::integer as price,
    months.observed_at
  from base cross join months
),
resolved as (
  select
    e.*,
    ma.id as make_id,
    mo.id as model_id,
    g.id  as generation_id
  from expanded e
  join public.makes       ma on ma.slug    = split_part(e.gen_slug, ':', 1)
  join public.models      mo on mo.make_id = ma.id and mo.slug = split_part(e.gen_slug, ':', 2)
  join public.generations g  on g.model_id = mo.id and g.slug  = split_part(e.gen_slug, ':', 3)
)
insert into public.ingested_price_points (
  source_slug, gen_slug, generation_id, model_id, make_id,
  external_id, year, km, price, currency, observed_at, ingest_run_id
)
select
  'seed',
  gen_slug,
  generation_id,
  model_id,
  make_id,
  concat_ws(':', gen_slug, year::text, observed_at::text),
  year,
  km,
  price,
  'EUR',
  observed_at,
  'seed-historical-backfill'
from resolved
on conflict (source_slug, external_id, ((observed_at at time zone 'UTC')::date))
do update set price = excluded.price;

-- Also add the 14 single-point snapshots at 2026-04-23 for the MV 30-day window.
insert into public.ingested_price_points (
  source_slug, gen_slug, generation_id, model_id, make_id,
  external_id, year, km, price, currency, observed_at, ingest_run_id
)
select
  'seed',
  b.gen_slug,
  g.id,
  mo.id,
  ma.id,
  concat_ws(':', b.gen_slug, b.year::text, '2026-04-23T00:00:00.000Z'),
  b.year,
  b.km,
  b.base_price,
  'EUR',
  '2026-04-23T00:00:00.000Z'::timestamptz,
  'seed-initial'
from (values
  ('mazda:mx-5:na',       1992::smallint, 150000,  8500),
  ('mazda:mx-5:na',       1995::smallint, 140000,  9200),
  ('mazda:mx-5:na',       1997::smallint, 130000, 10500),
  ('datsun:240z:s30',     1972::smallint, 120000, 52000),
  ('datsun:240z:s30',     1973::smallint, 115000, 48000),
  ('seat:leon:mk1',       2001::smallint, 180000,  2800),
  ('seat:leon:mk1',       2003::smallint, 165000,  3400),
  ('seat:leon:mk1',       2005::smallint, 150000,  4200),
  ('volkswagen:golf:mk4', 1999::smallint, 200000,  2500),
  ('volkswagen:golf:mk4', 2001::smallint, 185000,  3100),
  ('volkswagen:golf:mk4', 2003::smallint, 170000,  3800),
  ('audi:a3:8p',          2004::smallint, 180000,  4500),
  ('audi:a3:8p',          2006::smallint, 165000,  5800),
  ('audi:a3:8p',          2008::smallint, 150000,  7200)
) b(gen_slug, year, km, base_price)
join public.makes       ma on ma.slug    = split_part(b.gen_slug, ':', 1)
join public.models      mo on mo.make_id = ma.id and mo.slug = split_part(b.gen_slug, ':', 2)
join public.generations g  on g.model_id = mo.id and g.slug  = split_part(b.gen_slug, ':', 3)
on conflict (source_slug, external_id, ((observed_at at time zone 'UTC')::date))
do update set price = excluded.price;

select public.refresh_price_aggregates_daily();
