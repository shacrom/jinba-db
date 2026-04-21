insert into public.generations (model_id, slug, name_es, name_en, year_start, year_end, chassis_code)
select mo.id, v.slug, v.name_es, v.name_en, v.year_start, v.year_end, v.chassis
from (values
  ('mazda',      'mx-5', 'na',  'NA',          'NA (1ª gen)',  1989, 1997, 'NA'),
  ('datsun',     '240z', 's30', 'S30',         'S30',          1969, 1978, 'S30'),
  ('seat',       'leon', 'mk1', 'Mk1 (1M)',    'Mk1 (1M)',     1999, 2005, '1M'),
  ('volkswagen', 'golf', 'mk4', 'Mk4',         'Mk4',          1997, 2004, '1J'),
  ('audi',       'a3',   '8p',  '8P',          '8P',           2003, 2013, '8P')
) as v(make_slug, model_slug, slug, name_es, name_en, year_start, year_end, chassis)
join public.models mo on mo.slug = v.model_slug
join public.makes  ma on ma.id   = mo.make_id and ma.slug = v.make_slug
on conflict (model_id, slug) do nothing;
