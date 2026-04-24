-- =====================================================================
-- Seed: Audi RS6 C7 price backfill
-- Created: 2026-04-29 UTC  (taxonomy-rs6)
--
-- Seeds `ingested_price_points` with per-year medians for the Audi RS6
-- C7 (2013-2018) derived from research on Milanuncios / Coches.net /
-- Wallapop (April 2026). 12 monthly snapshots per (year) over
-- 2025-05 through 2026-04, plus an anchor row at 2026-04-23.
--
-- Idempotent via ipp_upsert_key.
-- =====================================================================

with base(gen_slug, year, km, base_price) as (
  values
    ('audi:rs6:c7', 2013::smallint, 200000, 44000),
    ('audi:rs6:c7', 2014::smallint, 170000, 50000),
    ('audi:rs6:c7', 2015::smallint, 155000, 55000),
    ('audi:rs6:c7', 2016::smallint, 120000, 65000),
    ('audi:rs6:c7', 2017::smallint,  95000, 75000),
    ('audi:rs6:c7', 2018::smallint,  75000, 90000)
),
months as (
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
  'seed-rs6-c7-research-2026-04'
from resolved
on conflict (source_slug, external_id, ((observed_at at time zone 'UTC')::date))
do update set price = excluded.price;

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
  'seed-rs6-c7-initial'
from (values
  ('audi:rs6:c7', 2013::smallint, 200000, 44000),
  ('audi:rs6:c7', 2014::smallint, 170000, 50000),
  ('audi:rs6:c7', 2015::smallint, 155000, 55000),
  ('audi:rs6:c7', 2016::smallint, 120000, 65000),
  ('audi:rs6:c7', 2017::smallint,  95000, 75000),
  ('audi:rs6:c7', 2018::smallint,  75000, 90000)
) b(gen_slug, year, km, base_price)
join public.makes       ma on ma.slug    = split_part(b.gen_slug, ':', 1)
join public.models      mo on mo.make_id = ma.id and mo.slug = split_part(b.gen_slug, ':', 2)
join public.generations g  on g.model_id = mo.id and g.slug  = split_part(b.gen_slug, ':', 3)
on conflict (source_slug, external_id, ((observed_at at time zone 'UTC')::date))
do update set price = excluded.price;

select public.refresh_price_aggregates_daily();
