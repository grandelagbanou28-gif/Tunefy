-- Tunefy Gospel catalog — 0002_gospel_artists (DDL ONLY)
-- Run this part first, THEN tell me "c'est bon" — I will seed the ~170 artists
-- through the API (service_role) right away, no need to paste the big list.

create table if not exists public.gospel_artists (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  type             text not null default 'artist',
  country          text,
  country_code     text,
  categories       text[] not null default '{}',
  languages        text[] not null default '{}',
  verified         boolean not null default false,
  image_url        text,
  official_website text,
  spotify_id       text,
  apple_music_id   text,
  youtube_channel_id text,
  source_url       text,
  last_verified    timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index if not exists gospel_artists_name_key
  on public.gospel_artists (lower(name));
create index if not exists gospel_artists_country_idx
  on public.gospel_artists (country_code);
create index if not exists gospel_artists_category_idx
  on public.gospel_artists using gin (categories);

alter table public.gospel_artists enable row level security;
drop policy if exists "gospel_artists_read" on public.gospel_artists;
create policy "gospel_artists_read" on public.gospel_artists
  for select using (true);

drop trigger if exists gospel_artists_touch on public.gospel_artists;
create trigger gospel_artists_touch before update on public.gospel_artists
  for each row execute function public.touch_updated_at();