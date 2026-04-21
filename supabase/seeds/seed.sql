-- Supabase runs a single seed.sql via `supabase db reset`.
-- Keep entities in separate files for readability, include them ordered here.
\i 01_sources.sql
\i 02_makes.sql
\i 03_models.sql
\i 04_generations.sql
\i 05_trims.sql
