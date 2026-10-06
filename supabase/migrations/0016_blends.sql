-- 0016_blends.sql
-- Shared "Blend" playlists: several devices build one playlist together.
--
-- Design
--   A Blend is one row keyed by a short human-readable join code
--   (e.g. "KORA-4821"). Whoever knows the code can read and contribute:
--   the code IS the invite, like Spotify Blend links. Members and tracks
--   live inside the `data` jsonb document (same whole-document pattern as
--   the per-user `playlists` table), so no join tables are needed.
--
--   data shape:
--     {
--       "name": "Afro Night",
--       "members": [{"uid": "<auth.uid>", "name": "Awa"}],
--       "tracks": [
--         {"song": {<MuzoItem json>}, "added_by_uid": "<uid>",
--          "added_by_name": "Awa", "added_at": "2026-10-06T..."}
--       ]
--     }
--
-- -- À exécuter dans le SQL Editor Supabase (Dashboard → SQL Editor) --
-- Idempotent: safe to run more than once.

create table if not exists public.blends (
  code       text primary key,
  name       text not null default 'Blend',
  data       jsonb not null default '{"members":[],"tracks":[]}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.blends is
  'Shared Blend playlists. The join code is the invite: anyone who knows it may read and contribute.';

alter table public.blends enable row level security;

-- Anyone (including anonymous app users) holding the code may read blends.
-- The app never lists the table, it always fetches by exact code.
drop policy if exists "blends_read" on public.blends;
create policy "blends_read" on public.blends
  for select using (true);

-- Anyone holding the code may create or update a blend (join = upsert with
-- themselves added, contribute = upsert with tracks appended).
drop policy if exists "blends_write" on public.blends;
create policy "blends_write" on public.blends
  for insert with check (true);

drop policy if exists "blends_update" on public.blends;
create policy "blends_update" on public.blends
  for update using (true) with check (true);

drop trigger if exists blends_touch_updated_at on public.blends;
create trigger blends_touch_updated_at
  before update on public.blends
  for each row execute function public.touch_updated_at();
