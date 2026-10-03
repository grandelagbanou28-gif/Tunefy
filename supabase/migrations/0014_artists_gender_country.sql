-- 0014_artists_gender_country.sql
-- Adds an explicit gender to the catalog and makes the country usable.
--
-- Why this exists
--   The catalog holds 1000 artists but has no way to express who they are:
--   `gender` did not exist, and `country_code` was empty on every row. The Home
--   genre shelves filter on country, so an empty column made those filters
--   return nothing, and there was no field left to guarantee representation.
--
--   Two requests are baked in:
--   - genres the app actually asks for ('fr rap', 'afro rap', 'hip hop' ...)
--     instead of the single broad key it used to look up, which did not exist;
--   - a gender value, so women are represented deliberately rather than by
--     whatever the popularity ranking happens to surface.
--
-- -- À exécuter dans le SQL Editor Supabase (Dashboard → SQL Editor) --
-- Idempotent: safe to run more than once.

-- 1) Genre + gender columns.
--    `gender` is a free-text label rather than an enum: MusicBrainz and Wikidata
--    disagree on spelling, and a CHECK constraint would reject legitimate
--    values instead of surfacing bad data.
alter table public.artists
  add column if not exists gender text,
  add column if not exists country_code text,
  add column if not exists genres_v2 text[] not null default '{}';

comment on column public.artists.gender is
  'Self-declared or curated gender (female/male/non-binary/unknown). Null means unknown, never assumed.';
comment on column public.artists.country_code is
  'ISO 3166-1 alpha-2 country of origin, e.g. FR, US, NG, CI.';

-- 2) Indexes that make the shelves' filters cheap.
create index if not exists artists_gender_idx on public.artists (gender);
create index if not exists artists_country_code_idx on public.artists (country_code);
create index if not exists artists_genres_v2_idx on public.artists using gin (genres_v2);

-- 3) Existing rows get a readable, searchable genre list.
--    The catalog stored a single broad genre; the app now asks for the keys it
--    really wants. Deriving the variants from the existing value means no row
--    has to be re-ingested for the shelves to start matching.
update public.artists
   set genres_v2 = array(
         select distinct lower(btrim(g::text))
         from unnest(coalesce(genres, '{}'::text[])) as g
         where btrim(g::text) <> ''
       )
 where coalesce(genres_v2, '{}'::text[]) = '{}';
