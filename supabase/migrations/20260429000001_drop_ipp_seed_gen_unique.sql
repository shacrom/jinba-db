-- =====================================================================
-- Migration: drop ipp_seed_gen_unique
-- Change:    data-sources-strategy (follow-up)
-- Created:   2026-04-29 00:00:01 UTC
--
-- IMMUTABLE ONCE MERGED TO main.
--
-- The partial unique index on (generation_id, source_slug) where
-- source_slug='seed' (introduced in 20260429000000_ingested_price_points.sql)
-- was overconstrained. The seed CSV has multiple year observations per
-- generation so M5 N-03 (per-gen median km/year) has more than one data
-- point. The primary upsert key `ipp_upsert_key` —
-- (source_slug, external_id, (observed_at at time zone 'UTC')::date) —
-- already provides the idempotency the cron handler relies on.
-- =====================================================================

begin;

drop index if exists public.ipp_seed_gen_unique;

commit;
