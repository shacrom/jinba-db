-- =====================================================================
-- Migration: init_core
-- Change:    db-schema-core
-- Created:   2026-04-20 12:00:00 UTC
--
-- IMMUTABLE ONCE MERGED TO main. Add new migrations for any correction.
-- =====================================================================

begin;

-- =====================================================================
-- 1. Taxonomy: makes -> models -> generations -> trims
-- =====================================================================

create table public.makes (
  id         bigint generated always as identity primary key,
  slug       text   not null unique,
  name_es    text   not null,
  name_en    text   not null,
  created_at timestamptz not null default now()
);

create table public.models (
  id         bigint generated always as identity primary key,
  make_id    bigint not null references public.makes(id) on delete restrict,
  slug       text   not null,
  name_es    text   not null,
  name_en    text   not null,
  created_at timestamptz not null default now(),
  unique (make_id, slug)
);

create table public.generations (
  id           bigint generated always as identity primary key,
  model_id     bigint   not null references public.models(id) on delete restrict,
  slug         text     not null,
  name_es      text     not null,
  name_en      text     not null,
  year_start   smallint not null,
  year_end     smallint,
  chassis_code text,
  created_at   timestamptz not null default now(),
  unique (model_id, slug),
  check (year_end is null or year_end >= year_start)
);

create table public.trims (
  id            bigint generated always as identity primary key,
  generation_id bigint   not null references public.generations(id) on delete restrict,
  slug          text     not null,
  name_es       text     not null,
  name_en       text     not null,
  power_hp      smallint,
  engine_code   text,
  created_at    timestamptz not null default now(),
  unique (generation_id, slug)
);

-- =====================================================================
-- 2. Scraping sources & telemetry
-- =====================================================================

create table public.sources (
  id             bigint generated always as identity primary key,
  slug           text   not null unique,
  display_name   text   not null,
  base_url       text   not null,
  fetch_strategy text   not null
                        check (fetch_strategy in ('cheerio','playwright')),
  rate_limit_ms  integer not null default 1500
                        check (rate_limit_ms >= 0),
  enabled        boolean not null default true,
  last_run_at    timestamptz,
  -- HI4: config MUST hold a `salt` (>= 16 chars) for seller_hash.
  config         jsonb   not null default '{}'::jsonb
                        check (config ? 'salt' and length(config->>'salt') >= 16),
  created_at     timestamptz not null default now()
);

create table public.scrape_runs (
  id            bigint generated always as identity primary key,
  source_id     bigint  not null references public.sources(id) on delete cascade,
  started_at    timestamptz not null default now(),
  finished_at   timestamptz,
  items_found   integer not null default 0,
  items_new     integer not null default 0,
  items_updated integer not null default 0,
  items_errored integer not null default 0,
  duration_ms   integer
);

create table public.scrape_errors (
  id          bigint generated always as identity primary key,
  run_id      bigint not null references public.scrape_runs(id) on delete cascade,
  url         text,
  error_type  text   not null,
  message     text   not null,
  occurred_at timestamptz not null default now()
);

-- =====================================================================
-- 3. Listings
--    PII BAN: no columns for seller phone/email/name. Only seller_hash.
-- =====================================================================

create table public.listings (
  id            bigint generated always as identity primary key,
  source_id     bigint  not null references public.sources(id) on delete restrict,
  external_id   text    not null,
  make_id       bigint  not null references public.makes(id) on delete restrict,
  model_id      bigint  not null references public.models(id) on delete restrict,
  generation_id bigint  not null references public.generations(id) on delete restrict,
  trim_id       bigint           references public.trims(id) on delete set null,
  year          smallint not null check (year between 1950 and 2100),
  km            integer   check (km >= 0),
  price         numeric(14,2) not null check (price >= 0),
  currency      text    not null check (currency ~ '^[A-Z]{3}$'),
  location_lat  double precision,
  location_lng  double precision,
  location_text text,
  status        text    not null default 'active'
                        check (status in ('active','sold','removed','expired')),
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  -- HI4: seller_hash is sha256(normalize(contact) || source_salt); 64 hex chars.
  seller_hash   text    not null check (seller_hash ~ '^[a-f0-9]{64}$'),
  url           text    not null,
  raw_html_ref  text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (source_id, external_id)
);

create table public.listing_snapshots (
  id             bigint generated always as identity primary key,
  listing_id     bigint  not null references public.listings(id) on delete cascade,
  captured_at    timestamptz not null default now(),
  price          numeric(14,2) not null,
  status         text    not null,
  changed_fields jsonb   not null default '{}'::jsonb
);

create table public.listing_photos (
  id                   bigint generated always as identity primary key,
  listing_id           bigint not null references public.listings(id) on delete cascade,
  position             smallint not null check (position >= 0),
  source_url           text   not null,
  storage_path         text,
  checksum             text,
  privacy_processed_at timestamptz,
  width                integer check (width is null or width > 0),
  height               integer check (height is null or height > 0),
  created_at           timestamptz not null default now(),
  unique (listing_id, position),
  -- MD6: anon RLS gates on privacy_processed_at IS NOT NULL; without a
  -- storage_path the thumbnail 404s. Refuse the state.
  constraint photos_privacy_implies_storage
    check (privacy_processed_at is null or storage_path is not null)
);

create table public.takedowns (
  id           bigint generated always as identity primary key,
  anuncio_hash text   not null,  -- sha256(source_slug || ':' || external_id); intentionally no FK.
  reason       text   not null
                      check (reason in ('seller_request','privacy','duplicate','fraud','other')),
  status       text   not null default 'pending'
                      check (status in ('pending','approved','rejected','resolved')),
  requested_at timestamptz not null default now(),
  resolved_at  timestamptz,
  updated_at   timestamptz not null default now(),  -- app code sets on UPDATE
  notes        text
);

-- =====================================================================
-- 4. Materialized view: price_aggregates_daily
--    Refreshed by edge function `refresh-price-aggregates` via external cron.
-- =====================================================================

-- HI2: `currency` is part of the grouping key. Mixing currencies in the same
-- bucket would silently corrupt medians (e.g. listings in ARS and USD). The
-- web filters by the locale/market's preferred currency.
create materialized view public.price_aggregates_daily as
select
  make_id,
  model_id,
  generation_id,
  currency,
  (year / 5) * 5                                        as year_bucket,
  date_trunc('day', last_seen_at)::date                 as date,
  count(*)                                              as count,
  percentile_cont(0.50) within group (order by price)   as median,
  percentile_cont(0.25) within group (order by price)   as p25,
  percentile_cont(0.75) within group (order by price)   as p75,
  avg(price)                                            as mean
from public.listings
where status = 'active'
group by make_id, model_id, generation_id, currency, year_bucket, date;

-- Unique index REQUIRED for REFRESH MATERIALIZED VIEW CONCURRENTLY.
create unique index pad_pk
  on public.price_aggregates_daily (make_id, model_id, generation_id, currency, year_bucket, date);

-- =====================================================================
-- 5. Justified indices
-- =====================================================================

-- Filter by car + order by price (primary UI query on listings pages).
create index listings_gen_price_idx
  on public.listings (generation_id, price);

-- Filter by car + year (year facet).
create index listings_gen_year_idx
  on public.listings (generation_id, year);

-- "Newest first" sort on home and listings index.
create index listings_first_seen_idx
  on public.listings (first_seen_at desc);

-- 95% of queries are on active listings; partial index is small and fast.
create index listings_active_idx
  on public.listings (generation_id, price)
  where status = 'active';

-- Price history chart per listing.
create index listing_snapshots_lid_time_idx
  on public.listing_snapshots (listing_id, captured_at desc);

-- Ordered gallery (already unique (listing_id, position), so this duplicates; keep explicit for clarity).
-- Takedown lookup before scrape insert.
create index takedowns_hash_idx
  on public.takedowns (anuncio_hash);

-- MD4: admin dashboard "pending takedowns" query path.
create index takedowns_pending_time_idx
  on public.takedowns (requested_at desc)
  where status = 'pending';

-- Debug UI / error drilldown.
create index scrape_errors_run_time_idx
  on public.scrape_errors (run_id, occurred_at);

-- =====================================================================
-- 6. Enable RLS and define policies
-- =====================================================================

-- Taxonomy tables: public read.
alter table public.makes        enable row level security;
alter table public.models       enable row level security;
alter table public.generations  enable row level security;
alter table public.trims        enable row level security;

-- HI5: collapsed policies (TO anon, authenticated) — single per table.
create policy makes_public_read       on public.makes       for select to anon, authenticated using (true);
create policy models_public_read      on public.models      for select to anon, authenticated using (true);
create policy generations_public_read on public.generations for select to anon, authenticated using (true);
create policy trims_public_read       on public.trims       for select to anon, authenticated using (true);

-- Sources: anon NOT allowed on base table (contains `config` with salts).
-- Web must use `sources_public` view below.
alter table public.sources enable row level security;
-- (no anon/authenticated policies = deny-all; only service_role reads config)

-- Listings: anon reads only active + sold; writes denied.
alter table public.listings enable row level security;
create policy listings_public_read on public.listings for select to anon, authenticated
  using (status in ('active','sold'));

-- Snapshots: public read (historical price data).
alter table public.listing_snapshots enable row level security;
create policy snapshots_public_read on public.listing_snapshots for select to anon, authenticated using (true);

-- Photos: only those with privacy processing done are public.
alter table public.listing_photos enable row level security;
create policy photos_public_read on public.listing_photos for select to anon, authenticated
  using (privacy_processed_at is not null);

-- Takedowns / scrape_runs / scrape_errors: deny-all for anon/authenticated.
alter table public.takedowns      enable row level security;
alter table public.scrape_runs    enable row level security;
alter table public.scrape_errors  enable row level security;
-- (no policies = deny-all; service_role manages)

-- =====================================================================
-- 7. Public views — column-level filtering for anon/authenticated.
--    Web clients SELECT from these, never from base tables.
-- =====================================================================

create view public.listings_public
with (security_invoker = true)
as
select
  id, source_id, external_id,
  make_id, model_id, generation_id, trim_id,
  year, km, price, currency,
  location_lat, location_lng, location_text,
  status, first_seen_at, last_seen_at, url,
  created_at, updated_at
from public.listings;

comment on view public.listings_public is
  'Public projection of listings. Excludes raw_html_ref and seller_hash.';

create view public.sources_public
with (security_invoker = true)
as
select id, slug, display_name, base_url, enabled
from public.sources
where enabled = true;

comment on view public.sources_public is
  'Public projection of sources. Excludes config (salts, credentials).';

-- Grant SELECT on views to anon and authenticated.
grant select on public.listings_public to anon, authenticated;
grant select on public.sources_public  to anon, authenticated;

-- =====================================================================
-- 8. Column-level grants for security_invoker views
--    Without this, Supabase's default blanket GRANT SELECT ON ALL TABLES
--    to anon would let clients bypass the views and read raw_html_ref,
--    seller_hash, and sources.config directly via PostgREST.
-- =====================================================================

revoke select on public.listings from anon, authenticated;
grant select (
  id, source_id, external_id,
  make_id, model_id, generation_id, trim_id,
  year, km, price, currency,
  location_lat, location_lng, location_text,
  status, first_seen_at, last_seen_at, url,
  created_at, updated_at
) on public.listings to anon, authenticated;

revoke select on public.sources from anon, authenticated;
grant select (id, slug, display_name, base_url, enabled)
  on public.sources to anon, authenticated;

-- =====================================================================
-- 9. Triggers — immutability + auto updated_at + append-only snapshots
-- =====================================================================

-- MD5: keep `updated_at` fresh on every UPDATE without relying on app code.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger listings_set_updated_at
  before update on public.listings
  for each row execute function public.set_updated_at();

create trigger takedowns_set_updated_at
  before update on public.takedowns
  for each row execute function public.set_updated_at();

-- HI3: listings.first_seen_at is immutable once written. Protects against
-- a future dev accidentally stomping it via an UPSERT UPDATE clause.
create or replace function public.listings_protect_first_seen_at()
returns trigger language plpgsql as $$
begin
  if new.first_seen_at is distinct from old.first_seen_at then
    raise exception 'listings.first_seen_at is immutable (was %, tried %)',
      old.first_seen_at, new.first_seen_at;
  end if;
  return new;
end;
$$;

create trigger listings_first_seen_immutable
  before update on public.listings
  for each row execute function public.listings_protect_first_seen_at();

-- MD8: listing_snapshots is an audit log. Block UPDATEs at the trigger level
-- — service_role should NEVER edit a historical snapshot.
--
-- Note: we intentionally DO NOT block DELETE so the FK's ON DELETE CASCADE
-- from listings still works (if the parent listing is removed, its history
-- goes with it). Explicit DELETE on snapshots alone is discouraged by
-- convention and RLS still denies anon/authenticated.
create or replace function public.listing_snapshots_no_update()
returns trigger language plpgsql as $$
begin
  raise exception 'listing_snapshots is append-only — UPDATE not allowed';
end;
$$;

create trigger listing_snapshots_no_update
  before update on public.listing_snapshots
  for each row execute function public.listing_snapshots_no_update();

-- =====================================================================
-- 10. refresh_price_aggregates_daily()
--    Invoked by the `refresh-price-aggregates` edge function (external cron).
--    Non-concurrent refresh because CONCURRENTLY cannot run inside the
--    plpgsql transaction; at MVP scale the SELECT lock is seconds.
-- =====================================================================

create or replace function public.refresh_price_aggregates_daily()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view public.price_aggregates_daily;
end;
$$;

revoke all on function public.refresh_price_aggregates_daily() from public, anon, authenticated;
grant execute on function public.refresh_price_aggregates_daily() to service_role;

commit;
