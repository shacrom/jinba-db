-- Sources of scraping (MVP).
-- `config.salt` is a LOCAL-DEV placeholder (≥16 chars to satisfy the CHECK
-- constraint). In production it MUST be rotated per-source via service_role
-- before the scraper runs, otherwise every listing's seller_hash collides
-- with the public dev value. See JINBA-HANDOFF.md op #3.
insert into public.sources (slug, display_name, base_url, fetch_strategy, rate_limit_ms, config)
values
  ('milanuncios', 'Milanuncios', 'https://www.milanuncios.com', 'cheerio',    2000,
    '{"salt":"dev-only-rotate-in-prod-please-01"}'::jsonb),
  ('wallapop',    'Wallapop',    'https://es.wallapop.com',     'playwright', 3500,
    '{"salt":"dev-only-rotate-in-prod-please-02"}'::jsonb)
on conflict (slug) do nothing;
