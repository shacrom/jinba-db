-- =====================================================================
-- Migration: seed Audi A3 8P trim lineup
-- Change:    a3-8p-expand-trims
-- Created:   2026-04-29 00:00:06 UTC
--
-- IMMUTABLE ONCE MERGED TO main.
--
-- Seeds the 12 most-relevant trims for the Audi A3 8P (2003-2013).
-- Engine codes are taken from the official Audi press packs and the SSP
-- 372 / 380 technical self-study programmes. Used as the reference
-- implementation for per-trim faults/mods; other generations will be
-- seeded later following the same shape.
-- =====================================================================

begin;

with gen as (
  select g.id
  from public.generations g
  join public.models mo on mo.id = g.model_id
  join public.makes ma on ma.id = mo.make_id
  where ma.slug = 'audi' and mo.slug = 'a3' and g.slug = '8p'
)
insert into public.trims (generation_id, slug, name_es, name_en, power_hp, engine_code)
select (select id from gen), slug, name_es, name_en, power_hp, engine_code
from (values
  ('1-6-fsi',        '1.6 FSI',          '1.6 FSI',          115, 'BAG'),
  ('1-4-tfsi',       '1.4 TFSI',         '1.4 TFSI',         125, 'CAXA'),
  ('1-8-tfsi',       '1.8 TFSI',         '1.8 TFSI',         160, 'CDAA'),
  ('2-0-tfsi',       '2.0 TFSI',         '2.0 TFSI',         200, 'AXX'),
  ('2-0-tfsi-s3',    'S3 2.0 TFSI',      'S3 2.0 TFSI',      265, 'CDLA'),
  ('3-2-v6',         '3.2 V6',           '3.2 V6',           250, 'BDB'),
  ('2-5-tfsi-rs3',   'RS3 2.5 TFSI',     'RS3 2.5 TFSI',     340, 'CEPA'),
  ('1-9-tdi-pd',     '1.9 TDI PD',       '1.9 TDI PD',       105, 'BKC'),
  ('2-0-tdi-pd-140', '2.0 TDI PD 140',   '2.0 TDI PD 140',   140, 'BKD'),
  ('2-0-tdi-pd-170', '2.0 TDI PD 170',   '2.0 TDI PD 170',   170, 'BMN'),
  ('1-6-tdi-cr',     '1.6 TDI CR',       '1.6 TDI CR',       105, 'CAYC'),
  ('2-0-tdi-cr',     '2.0 TDI CR',       '2.0 TDI CR',       140, 'CBAB')
) as t(slug, name_es, name_en, power_hp, engine_code)
on conflict (generation_id, slug) do update set
  name_es     = excluded.name_es,
  name_en     = excluded.name_en,
  power_hp    = excluded.power_hp,
  engine_code = excluded.engine_code;

commit;
