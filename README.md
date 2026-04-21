# jinba-db

Source of truth for the Supabase schema used by [`jinba-web`](https://github.com/shacrom/jinba-web) and [`jinba-scraper`](https://github.com/shacrom/jinba-scraper).

Contains migrations, seeds, Edge Functions, and generated TypeScript types.

## Prerequisites

- **Node 24 LTS** (`node -v` → 24.x)
- **Docker Desktop** (for local Supabase via `supabase start`)
- **Supabase CLI** → install via Homebrew on macOS: `brew install supabase/tap/supabase`. Alternative: `npx supabase` on every command.

## Quick start

```bash
npm install
supabase start          # spins up local Postgres + Studio + Storage (needs Docker)
npm run db:reset        # applies migrations and seeds to the local DB
```

Local Studio opens at http://localhost:54323.

## Linking to a cloud project

Type generation and `db push` require a linked project. Run once per clone:

```bash
supabase login
supabase link --project-ref <your-project-ref>
```

Copy `.env.example` to `.env.local` and fill in the values (never commit `.env.local`).

> First time after cloning: `mv env.example .env.example` (the repo ships the template as `env.example` because the agent sandbox blocked dotfile writes; rename once locally and commit if desired).

## Scripts

| Script | Purpose |
|---|---|
| `npm run db:reset` | Drop, recreate, apply migrations, run seeds (local DB). |
| `npm run db:push` | Push pending migrations to the linked cloud project. |
| `npm run types:gen` | Regenerate `types/database.ts` from the schema. |
| `npm run types:check` | Fail if `types/database.ts` is stale (used in CI). |
| `npm run lint` | Biome lint over `scripts/` and `supabase/functions/`. |
| `npm run format` | Biome format (write). |

## Migration policy

- Migrations under `supabase/migrations/` are **immutable once merged to `main`**. Never edit a merged migration — add a new one.
- Filename convention: `YYYYMMDDHHMMSS_slug.sql` (UTC, slug `[a-z0-9_]+`). The initial migration is `20260420120000_init_core.sql`.
- Schema-affecting changes go ONLY through a new migration. No DDL lives outside `supabase/migrations/`.
- **PII ban**: `listings` and related tables MUST NOT contain columns for seller phone, email, or name. Only anonymized `seller_hash` is permitted.

## Seeds

`supabase/seeds/seed.sql` is the entry point Supabase runs. It `\i`-includes the entity files in order:

1. `01_sources.sql` — scraping portals (Milanuncios, Wallapop for MVP).
2. `02_makes.sql` — 5 makes (Mazda, Datsun, SEAT, Volkswagen, Audi).
3. `03_models.sql` — 5 models linked to makes.
4. `04_generations.sql` — 5 generations with year ranges and chassis codes (NA, S30, MK1, MK4, 8P).
5. `05_trims.sql` — 5 trims with power and engine code.

All inserts use `ON CONFLICT DO NOTHING` → running `db:reset` twice yields identical counts.

## Schema overview

- **Taxonomy**: `makes → models → generations → trims` (fully generic, bilingual `name_es` + `name_en`).
- **Listings**: UNIQUE on `(source_id, external_id)`. Nullable FK to `trims` when the trim can't be identified.
- **Snapshots**: append-only history of price/status changes per listing.
- **Photos**: original URL + optional Supabase Storage path + `privacy_processed_at` flag (anon only sees processed photos).
- **Takedowns**: referenced by `anuncio_hash` (no FK) so they survive listing deletion.
- **Telemetry**: `sources` + `scrape_runs` + `scrape_errors`.
- **Aggregates**: `price_aggregates_daily` materialized view, refreshed hourly by the `refresh-price-aggregates` Edge Function (external cron).
- **Public views**: `listings_public` and `sources_public` strip secret columns; web clients query views, never base tables.

## RLS summary

| Role | Access |
|---|---|
| `service_role` | Full bypass (scraper, migrations, functions). |
| `anon` | SELECT on taxonomy, `listings_public`, `sources_public`, snapshots, processed photos. All writes denied. |
| `authenticated` | Same as `anon` for now; reserved for F2+ features (favorites, alerts). |

## Edge Functions

### `refresh-price-aggregates`

Refreshes the materialized view. Invoke via HTTPS after deploy:

```bash
curl -X POST "https://<project>.functions.supabase.co/refresh-price-aggregates" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"
```

Schedule hourly via [cron-job.org](https://cron-job.org) or a scheduled GitHub Actions workflow until Supabase cron triggers are available on your plan.

## CI

| Workflow | When | What |
|---|---|---|
| `migrations-check.yml` | PR | Spin ephemeral Postgres, apply migrations + seeds, fail if `types/database.ts` is stale. |
| `deploy-staging.yml` | merge to `main` | `supabase db push` to the staging project, deploy Edge Functions. |

Required GitHub secrets:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_STAGING_PROJECT_REF`
- `SUPABASE_STAGING_DB_PASSWORD`

Production deploys are **manual** and promoted from staging — no automation at MVP.

## Contributing

1. Branch off `main`.
2. Add a NEW migration file (never edit merged ones).
3. Run `npm run db:reset` locally to verify it applies cleanly.
4. Run `npm run types:gen` and commit the updated `types/database.ts`.
5. Open a PR — `migrations-check` must pass.

## License

MIT (see `LICENSE`).
