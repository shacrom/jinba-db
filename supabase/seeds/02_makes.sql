insert into public.makes (slug, name_es, name_en) values
  ('mazda',      'Mazda',      'Mazda'),
  ('datsun',     'Datsun',     'Datsun'),
  ('seat',       'SEAT',       'SEAT'),
  ('volkswagen', 'Volkswagen', 'Volkswagen'),
  ('audi',       'Audi',       'Audi')
on conflict (slug) do nothing;
