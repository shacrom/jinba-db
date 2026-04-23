-- =====================================================================
-- Migration: ingested_price_points + MV extension
-- Change:    data-sources-strategy
-- Created:   2026-04-29 00:00:00 UTC
--
-- IMMUTABLE ONCE MERGED TO main. Add new migrations for any correction.
--
-- Purpose: introduce a staging table fed by the new Apify-based ingest cron
-- in jinba-web (/api/cron/sync-prices) and extend `price_aggregates_daily`
-- so it UNIONs the existing `listings` feed with the new staging rows.
-- Downstream MV consumers (jinba-web calculator, price chart, LivePriceStats)
-- stay untouched — same columns, same PK, same grants.
-- =====================================================================

begin;

-- =====================================================================
-- 1. Staging table
-- =====================================================================

create table public.ingested_price_points (
  id            bigint generated always as identity primary key,
  source_slug   text    not null
                        check (source_slug in ('milanuncios','wallapop','seed')),
  gen_slug      text    not null,
  generation_id bigint  not null references public.generations(id) on delete restrict,
  model_id      bigint  not null references public.models(id)      on delete restrict,
  make_id       bigint  not null references public.makes(id)       on delete restrict,
  external_id   text    not null,
  year          smallint not null check (year between 1950 and 2100),
  km            integer    check (km is null or km >= 0),
  price         numeric(14,2) not null check (price >= 0),
  currency      text    not null default 'EUR' check (currency ~ '^[A-Z]{3}$'),
  observed_at   timestamptz not null,
  ingest_run_id text    not null,
  created_at    timestamptz not null default now()
);

-- Upsert key: same listing re-observed in the same UTC day updates the row;
-- daily granularity matches how the MV groups. Expression-based unique
-- constraints must be declared as CREATE UNIQUE INDEX (Postgres doesn't
-- accept expressions in inline table UNIQUE clauses).
create unique index ipp_upsert_key
  on public.ingested_price_points (source_slug, external_id, ((observed_at at time zone 'UTC')::date));

-- Mirror the MV grouping key so the materialize step doesn't need a seq scan.
create index ipp_mv_key_idx
  on public.ingested_price_points (make_id, model_id, generation_id, currency, year, observed_at);

-- TTL-style purges in the future iterate by date.
create index ipp_observed_at_idx
  on public.ingested_price_points (observed_at);

-- RLS deny-all. service_role bypasses RLS; anon/authenticated never read
-- this table directly — only via the MV below.
alter table public.ingested_price_points enable row level security;

-- Partial unique index for seed upserts — keeps the re-run of the monthly
-- seed cron idempotent across niche gens when observed_at is bumped.
create unique index ipp_seed_gen_unique
  on public.ingested_price_points (generation_id, source_slug)
  where source_slug = 'seed';

-- =====================================================================
-- 2. Rebuild `price_aggregates_daily` to UNION listings + staging
-- =====================================================================

-- Postgres cannot CREATE OR REPLACE a materialized view with a different
-- SELECT shape. DROP + CREATE inside one transaction keeps the rebuild atomic.
drop materialized view if exists public.price_aggregates_daily cascade;

create materialized view public.price_aggregates_daily as
with unioned as (
  -- Existing listings path, unchanged logic.
  select
    make_id,
    model_id,
    generation_id,
    currency,
    year,
    date_trunc('day', last_seen_at)::date as date,
    price
  from public.listings
  where status = 'active'

  union all

  -- New staging path. Every inserted row is by definition active — no status.
  select
    make_id,
    model_id,
    generation_id,
    currency,
    year,
    date_trunc('day', observed_at)::date as date,
    price
  from public.ingested_price_points
)
select
  make_id,
  model_id,
  generation_id,
  currency,
  (year / 5) * 5                                        as year_bucket,
  date,
  count(*)                                              as count,
  percentile_cont(0.50) within group (order by price)   as median,
  percentile_cont(0.25) within group (order by price)   as p25,
  percentile_cont(0.75) within group (order by price)   as p75,
  avg(price)                                            as mean
from unioned
group by make_id, model_id, generation_id, currency, year_bucket, date;

-- PK unchanged — jinba-web callers stay compatible.
create unique index pad_pk
  on public.price_aggregates_daily (make_id, model_id, generation_id, currency, year_bucket, date);

-- CASCADE dropped any grants on the old MV. Re-grant for anon/authenticated
-- read so the frontend keeps working after the migration.
grant select on public.price_aggregates_daily to anon, authenticated;

commit;
