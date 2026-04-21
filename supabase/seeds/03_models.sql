insert into public.models (make_id, slug, name_es, name_en)
select ma.id, v.slug, v.name_es, v.name_en
from (values
  ('mazda',      'mx-5',   'MX-5',  'MX-5'),
  ('datsun',     '240z',   '240Z',  '240Z'),
  ('seat',       'leon',   'León',  'Leon'),
  ('volkswagen', 'golf',   'Golf',  'Golf'),
  ('audi',       'a3',     'A3',    'A3')
) as v(make_slug, slug, name_es, name_en)
join public.makes ma on ma.slug = v.make_slug
on conflict (make_id, slug) do nothing;
