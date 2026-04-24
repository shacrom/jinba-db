-- =====================================================================
-- Migration: user system — profiles + user_cars + user_watchlist
-- Change:    f2-user-system
-- Created:   2026-04-29 00:00:05 UTC
--
-- IMMUTABLE ONCE MERGED TO main.
--
-- Introduces the F2 user layer: public profile per auth.users row with a
-- role enum (user | admin), plus two user-owned tables (garage and
-- watchlist) backed by strict RLS so one user's rows are invisible to
-- every other authenticated user. Service-role bypasses RLS for admin
-- tooling as usual.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- profiles — one row per auth.users row, auto-populated via trigger
-- ---------------------------------------------------------------------

create type public.user_role as enum ('user', 'admin');

create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role         public.user_role not null default 'user',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Trigger: when a new auth.users row is created, insert a matching profile.
-- Uses SECURITY DEFINER so it can write to public.profiles from the auth
-- schema's insert trigger context.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- user_cars — cars that a user owns (garage)
-- ---------------------------------------------------------------------

create table public.user_cars (
  id                  bigint generated always as identity primary key,
  user_id             uuid not null references auth.users(id) on delete cascade,
  generation_id       bigint not null references public.generations(id) on delete restrict,
  year                smallint not null check (year between 1950 and 2100),
  km                  integer check (km is null or km >= 0),
  purchased_at        date,
  purchase_price_eur  integer check (purchase_price_eur is null or purchase_price_eur >= 0),
  notes               text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index user_cars_user_idx on public.user_cars (user_id, created_at desc);

-- ---------------------------------------------------------------------
-- user_watchlist — generations a user is researching
-- ---------------------------------------------------------------------

create table public.user_watchlist (
  id                bigint generated always as identity primary key,
  user_id           uuid not null references auth.users(id) on delete cascade,
  generation_id     bigint not null references public.generations(id) on delete restrict,
  target_price_eur  integer check (target_price_eur is null or target_price_eur >= 0),
  notes             text,
  added_at          timestamptz not null default now(),
  -- One watchlist entry per (user, gen). Users update instead of duplicating.
  unique (user_id, generation_id)
);

create index user_watchlist_user_idx on public.user_watchlist (user_id, added_at desc);

-- ---------------------------------------------------------------------
-- RLS policies — users see/edit only their own rows; admins via service-role.
-- ---------------------------------------------------------------------

alter table public.profiles      enable row level security;
alter table public.user_cars     enable row level security;
alter table public.user_watchlist enable row level security;

-- profiles: each user reads/updates their own row; nobody can insert
-- directly (the trigger handles it) nor delete (cascade from auth.users).
create policy profiles_select_own on public.profiles
  for select to authenticated using (auth.uid() = id);

create policy profiles_update_own on public.profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- user_cars: full CRUD on own rows.
create policy user_cars_select_own on public.user_cars
  for select to authenticated using (auth.uid() = user_id);
create policy user_cars_insert_own on public.user_cars
  for insert to authenticated with check (auth.uid() = user_id);
create policy user_cars_update_own on public.user_cars
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy user_cars_delete_own on public.user_cars
  for delete to authenticated using (auth.uid() = user_id);

-- user_watchlist: full CRUD on own rows.
create policy user_watchlist_select_own on public.user_watchlist
  for select to authenticated using (auth.uid() = user_id);
create policy user_watchlist_insert_own on public.user_watchlist
  for insert to authenticated with check (auth.uid() = user_id);
create policy user_watchlist_update_own on public.user_watchlist
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy user_watchlist_delete_own on public.user_watchlist
  for delete to authenticated using (auth.uid() = user_id);

-- ---------------------------------------------------------------------
-- is_admin() helper — used by admin RLS and by server-side gates
-- ---------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated, anon;

-- Admins can read all profiles (for the /admin/users page).
create policy profiles_admin_read_all on public.profiles
  for select to authenticated using (public.is_admin());
-- Admins can update any profile (for role promotion/demotion).
create policy profiles_admin_update_all on public.profiles
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

commit;
