-- 0015_user_content_state.sql
-- Per-user refresh state, so content is refreshed *for each user* rather than
-- on one global 12h timer shared by everyone.
--
-- Why this exists
--   CuratedArtistsService is a singleton with a fixed timer: whoever opens the
--   app first pays for the download, and every other user keeps the same data
--   until the timer fires again. Two people opening the app ten minutes apart
--   get identical content for the next twelve hours, and nobody's own staleness
--   is ever considered. With per-user rotations on top (see
--   content_identity.dart), the catalogue was still one shared snapshot.
--
--   This table records each user's own last refresh so freshness is judged
--   against the user who is waiting, not against a global clock.
--
-- -- À exécuter dans le SQL Editor Supabase (Dashboard → SQL Editor) --
-- Idempotent: safe to run more than once.

create table if not exists public.user_content_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  -- When this user's own copy of the catalogue was last refreshed. NULL means
  -- never, which makes the first open a refresh.
  catalog_refreshed_at timestamptz,
  -- Per-user knobs, so "my content refreshes for me" can grow beyond a timer.
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column public.user_content_state.catalog_refreshed_at is
  'Per-user catalogue freshness. NULL = never refreshed for this user.';

alter table public.user_content_state
  enable row level security;

-- A user may read their own row only. This is the whole point of the table:
-- one user's refresh must never decide another user's content.
drop policy if exists "user_content_state_own" on public.user_content_state;
create policy "user_content_state_own" on public.user_content_state
  for select
  using (auth.uid() = user_id);

drop policy if exists "user_content_state_own_update" on public.user_content_state;
create policy "user_content_state_own_update" on public.user_content_state
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "user_content_state_own_upsert" on public.user_content_state;
create policy "user_content_state_own_upsert" on public.user_content_state
  for update
  using (auth.uid() = user_id);

create index if not exists user_content_state_refreshed_idx
  on public.user_content_state (catalog_refreshed_at);