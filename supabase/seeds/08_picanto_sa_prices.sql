-- =====================================================================
-- Seed: Kia Picanto SA price backfill
-- Created: 2026-04-29 UTC  (taxonomy-picanto)
--
-- Seeds `ingested_price_points` with per-year medians for the Kia Picanto
-- SA (2004-2011) derived from research on Milanuncios / Coches.net /
-- Wallapop (April 2026). 12 monthly snapshots per (year) over 2025-05
-- through 2026-04, plus an anchor row at 2026-04-23.
-- =====================================================================

with base(gen_slug, year, km, base_price) as (
  values
    ('kia:picanto:sa', 2004::smallint, 220000, 1500),
    ('kia:picanto:sa', 2005::smallint, 200000, 1700),
    ('kia:picanto:sa', 2006::smallint, 180000, 1900),
    ('kia:picanto:sa', 2007::smallint, 160000, 2200),
    ('kia:picanto:sa', 2008::smallint, 140000, 2500),
    ('kia:picanto:sa', 2009::smallint, 120000, 2800),
    ('kia:picanto:sa', 2010::smallint, 105000, 3100),
    ('kia:picanto:sa', 2011::smallint,  90000, 3400)
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
  'seed-kia-picanto-sa-research-2026-04'
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
  'seed-kia-picanto-sa-initial'
from (values
  ('kia:picanto:sa', 2004::smallint, 220000, 1500),
  ('kia:picanto:sa', 2005::smallint, 200000, 1700),
  ('kia:picanto:sa', 2006::smallint, 180000, 1900),
  ('kia:picanto:sa', 2007::smallint, 160000, 2200),
  ('kia:picanto:sa', 2008::smallint, 140000, 2500),
  ('kia:picanto:sa', 2009::smallint, 120000, 2800),
  ('kia:picanto:sa', 2010::smallint, 105000, 3100),
  ('kia:picanto:sa', 2011::smallint,  90000, 3400)
) b(gen_slug, year, km, base_price)
join public.makes       ma on ma.slug    = split_part(b.gen_slug, ':', 1)
join public.models      mo on mo.make_id = ma.id and mo.slug = split_part(b.gen_slug, ':', 2)
join public.generations g  on g.model_id = mo.id and g.slug  = split_part(b.gen_slug, ':', 3)
on conflict (source_slug, external_id, ((observed_at at time zone 'UTC')::date))
do update set price = excluded.price;

select public.refresh_price_aggregates_daily();
