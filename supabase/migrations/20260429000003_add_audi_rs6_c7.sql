-- =====================================================================
-- Migration: add Audi RS6 C7 (model + generation)
-- Change:    taxonomy-rs6
-- Created:   2026-04-29 00:00:03 UTC
--
-- IMMUTABLE ONCE MERGED TO main.
--
-- Adds the Audi RS6 C7 (2013-2018) to the taxonomy so the model page
-- renders, the calculator accepts it, and the ingest pipeline can
-- target its dataset IDs.
-- =====================================================================

begin;

-- Model: audi/rs6
insert into public.models (make_id, slug, name_es, name_en)
select ma.id, 'rs6', 'RS6', 'RS6'
from public.makes ma
where ma.slug = 'audi'
on conflict (make_id, slug) do nothing;

-- Generation: audi/rs6/c7 (2013-2018)
-- C7 covers pre-facelift (2013-2015, 560 hp V8 TFSI biturbo) and the
-- facelift / Performance trim (2016-2018, 605 hp Performance). Treat as
-- a single taxonomy entry for the used market — buyers shop by model
-- year and equipment level, not facelift number.
insert into public.generations (
  model_id, slug, name_es, name_en, year_start, year_end, chassis_code
)
select mo.id, 'c7', 'C7', 'C7', 2013::smallint, 2018::smallint, 'C7'
from public.models mo
join public.makes ma on ma.id = mo.make_id
where ma.slug = 'audi' and mo.slug = 'rs6'
on conflict (model_id, slug) do nothing;

commit;
