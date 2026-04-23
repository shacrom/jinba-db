-- =====================================================================
-- Migration: get_median_km_per_year function
-- Change:    data-sources-strategy / M5 N-03
-- Created:   2026-04-29 00:00:02 UTC
--
-- IMMUTABLE ONCE MERGED TO main.
--
-- Exposes a per-generation median km/year to the anon client without
-- granting SELECT on the staging table. SECURITY DEFINER reads the
-- aggregate internally and returns a single scalar — deny-all RLS on
-- `ingested_price_points` stays intact.
--
-- Returns 15_000 (the product-wide baseline in jinba-web/src/lib/price-
-- estimate.ts) when the generation has fewer than 3 km observations —
-- signal too noisy to trust.
-- =====================================================================

begin;

create or replace function public.get_median_km_per_year(gen_id bigint)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  observation_count integer;
  result numeric;
begin
  with km_year as (
    select km::numeric / greatest(
      extract(year from now())::int - year, 1
    ) as kmy
    from public.ingested_price_points
    where generation_id = gen_id
      and km is not null
      and km > 0
  )
  select count(*), percentile_cont(0.5) within group (order by kmy)
  into observation_count, result
  from km_year;

  if observation_count < 3 or result is null then
    return 15000;
  end if;

  return round(result)::integer;
end;
$$;

revoke all on function public.get_median_km_per_year(bigint) from public, anon, authenticated;
grant execute on function public.get_median_km_per_year(bigint) to anon, authenticated, service_role;

commit;
