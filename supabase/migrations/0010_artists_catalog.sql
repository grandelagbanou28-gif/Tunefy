-- Tunefy Artists Catalog — 0010_artists_catalog
-- Table publique de masse : artistes du monde entier, chacun avec ses catégories.
-- Alimentée par le pipeline seed (MusicBrainz/Deezer) via service_role.
-- L'app la lit en REST (anon) par catégorie paginée.

create table if not exists public.artists (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null,
  type        text not null default 'artist',
  country     text,
  country_code text,
  categories  text[] not null default '{}',
  genres      text[] not null default '{}',
  languages   text[] not null default '{}',
  image_url   text,
  thumb_url   text,
  popularity  integer not null default 0,
  mb_id       text,
  deezer_id   text,
  spotify_id  text,
  musicbrainz_id text,
  source      text not null default 'musicbrainz',
  verified    boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create unique index if not exists artists_slug_key on public.artists (slug);
create index if not exists artists_name_lower_idx on public.artists (lower(name));
create index if not exists artists_country_idx on public.artists (country_code);
create index if not exists artists_category_idx on public.artists using gin (categories);
create index if not exists artists_popularity_idx on public.artists (popularity desc);
create index if not exists artists_mb_id_idx on public.artists (mb_id);

alter table public.artists enable row level security;

drop policy if exists "artists_read" on public.artists;
create policy "artists_read" on public.artists
  for select using (true);

drop policy if exists "artists_manage" on public.artists;
create policy "artists_manage" on public.artists
  for all
  to service_role
  using (true)
  with check (true);

drop trigger if exists artists_touch on public.artists;
create trigger artists_touch before update on public.artists
  for each row execute function public.touch_updated_at();

-- Albums liés aux artistes (facultatif, pour enrichir)
create table if not exists public.albums (
  id         uuid primary key default gen_random_uuid(),
  artist_id  uuid references public.artists(id) on delete cascade,
  name       text not null,
  image_url  text,
  year       integer,
  created_at timestamptz not null default now()
);
create index if not exists albums_artist_idx on public.albums (artist_id);
create index if not exists albums_name_idx on public.albums (lower(name));

alter table public.albums enable row level security;
drop policy if exists "albums_read" on public.albums;
create policy "albums_read" on public.albums for select using (true);

-- Chansons avec videoId (flux audio complet résolu via yt-dlp à distance)
create table if not exists public.songs (
  id         uuid primary key default gen_random_uuid(),
  artist_id  uuid references public.artists(id) on delete cascade,
  album_id   uuid references public.albums(id) on delete set null,
  title      text not null,
  video_id   text,
  duration_ms integer,
  image_url  text,
  audio_url  text,
  play_count integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists songs_artist_idx on public.songs (artist_id);
create index if not exists songs_title_idx on public.songs (lower(title));
create unique index if not exists songs_video_id_key on public.songs (video_id) where video_id is not null;

alter table public.songs enable row level security;
drop policy if exists "songs_read" on public.songs;
create policy "songs_read" on public.songs for select using (true);

-- Fonction RPC : artistes paginés par catégorie
create or replace function public.artists_by_category(
  p_category text,
  p_limit integer default 20,
  p_offset integer default 0
)
returns setof public.artists
language sql stable
as $$
  select a.*
  from public.artists a
  where p_category = any(a.categories)
  order by a.popularity desc, a.name asc
  limit p_limit offset p_offset;
$$;

-- Fonction RPC : recherche d'artistes par nom
create or replace function public.search_artists(
  p_query text,
  p_limit integer default 20
)
returns setof public.artists
language sql stable
as $$
  select a.*
  from public.artists a
  where a.name ilike '%' || p_query || '%'
  order by a.popularity desc, a.name asc
  limit p_limit;
$$;