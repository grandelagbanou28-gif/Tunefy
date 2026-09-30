-- Tunefy Artists Catalog — 0011_artists_catalog_v2
-- Adapte la table public.artists EXISTANTE (structure incomplète + 2204 placeholders)
-- aux besoins : catégories, slug, popularité, ids de sources, et RPC de pagination.
--
-- -- À exécuter dans le SQL Editor Supabase (Dashboard → SQL Editor) -- 
--
-- Contexte : la table artists existait déjà (colonnes id,name,image_url,country,
-- country_code,region,genres,bio,verified,followers,created_at,updated_at) avec
-- ~2204 lignes placeholder (noms numériques vides). Rien dans l'app ne l'utilise.

-- 1) Nettoyer les placeholders (noms purement numériques / vides)
delete from public.artists
where name is null
   or name = ''
   or name ~ '^[0-9]+$';

-- 2) Ajouter les colonnes manquantes (idempotent)
alter table public.artists
  add column if not exists slug text,
  add column if not exists categories text[] not null default '{}',
  add column if not exists popularity integer not null default 0,
  add column if not exists mb_id text,
  add column if not exists deezer_id text,
  add column if not exists spotify_id text,
  add column if not exists musicbrainz_id text,
  add column if not exists source text not null default 'musicbrainz',
  add column if not exists thumb_url text;

-- 3) Remplir slug + catégories par défaut sur les lignes restantes
update public.artists
set slug = coalesce(slug, lower(regexp_replace(name, '[^a-z0-9]+', '-', 'g')) || '-' || substr(md5(name), 1, 6));

-- 4) Index pour perf / pagination
create index if not exists artists_slug_idx on public.artists (slug);
create index if not exists artists_name_lower_idx on public.artists (lower(name));
create index if not exists artists_category_idx on public.artists using gin (categories);
create index if not exists artists_popularity_idx on public.artists (popularity desc);
create index if not exists artists_mb_id_idx on public.artists (mb_id);

-- 5) RLS : lecture publique, écriture service_role uniquement
alter table public.artists enable row level security;
drop policy if exists "artists_read" on public.artists;
create policy "artists_read" on public.artists for select using (true);
drop policy if exists "artists_manage" on public.artists;
create policy "artists_manage" on public.artists
  for all to service_role using (true) with check (true);

-- 6) RPC : artistes paginés par catégorie
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

-- 7) RPC : recherche d'artistes par nom
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

-- 8) (Optionnel) tables albums + songs si pas déjà présentes
create table if not exists public.albums (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid references public.artists(id) on delete cascade,
  name text not null,
  image_url text,
  year integer,
  created_at timestamptz not null default now()
);
create index if not exists albums_artist_idx on public.albums (artist_id);
alter table public.albums enable row level security;
drop policy if exists "albums_read" on public.albums;
create policy "albums_read" on public.albums for select using (true);

create table if not exists public.songs (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid references public.artists(id) on delete cascade,
  album_id uuid references public.albums(id) on delete set null,
  title text not null,
  video_id text,
  duration_ms integer,
  image_url text,
  audio_url text,
  play_count integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists songs_artist_idx on public.songs (artist_id);
create unique index if not exists songs_video_id_idx on public.songs (video_id) where video_id is not null;
alter table public.songs enable row level security;
drop policy if exists "songs_read" on public.songs;
create policy "songs_read" on public.songs for select using (true);