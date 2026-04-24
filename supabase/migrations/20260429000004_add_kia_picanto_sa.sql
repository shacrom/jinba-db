-- =====================================================================
-- Migration: add Kia Picanto SA (model + generation + make)
-- Change:    taxonomy-picanto
-- Created:   2026-04-29 00:00:04 UTC
--
-- IMMUTABLE ONCE MERGED TO main.
--
-- Adds Kia as a new make, Picanto as its first model, and the SA
-- generation (2004-2011) — Spanish A-segment volume favourite.
-- =====================================================================

begin;

insert into public.makes (slug, name_es, name_en)
values ('kia', 'KIA', 'Kia')
on conflict (slug) do nothing;

insert into public.models (make_id, slug, name_es, name_en)
select ma.id, 'picanto', 'Picanto', 'Picanto'
from public.makes ma
where ma.slug = 'kia'
on conflict (make_id, slug) do nothing;

insert into public.generations (
  model_id, slug, name_es, name_en, year_start, year_end, chassis_code
)
select mo.id, 'sa', 'SA', 'SA', 2004::smallint, 2011::smallint, 'SA'
from public.models mo
join public.makes ma on ma.id = mo.make_id
where ma.slug = 'kia' and mo.slug = 'picanto'
on conflict (model_id, slug) do nothing;

commit;
