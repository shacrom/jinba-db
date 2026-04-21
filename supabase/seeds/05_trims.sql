insert into public.trims (generation_id, slug, name_es, name_en, power_hp, engine_code)
select g.id, v.slug, v.name_es, v.name_en, v.hp, v.engine
from (values
  ('mazda',      'mx-5', 'na',  '1-6',      '1.6',          '1.6 (NA6)',   115, 'B6'),
  ('datsun',     '240z', 's30', 'l24',      'L24',          'L24 2.4L I6', 151, 'L24'),
  ('seat',       'leon', 'mk1', 'cupra-r',  'Cupra R',      'Cupra R',     210, 'BAM'),
  ('volkswagen', 'golf', 'mk4', 'r32',      'R32',          'R32',         241, 'BFH'),
  ('audi',       'a3',   '8p',  's3',       'S3',           'S3 8P',       265, 'CDLA')
) as v(make_slug, model_slug, gen_slug, slug, name_es, name_en, hp, engine)
join public.generations g on g.slug = v.gen_slug
join public.models      mo on mo.id = g.model_id and mo.slug = v.model_slug
join public.makes       ma on ma.id = mo.make_id and ma.slug = v.make_slug
on conflict (generation_id, slug) do nothing;
