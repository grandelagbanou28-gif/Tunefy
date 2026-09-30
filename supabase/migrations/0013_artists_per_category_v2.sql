-- Tunefy Artists Catalog — 0013_artists_per_category_v2
-- Remplace les 12 tables par-catégorie (0012) par les 5 tables du nouveau
-- HOME. Chaque artiste vit dans EXACTEMENT une table.
--
-- Peuplement par SEEDS (category_artist_seeds) au lieu de genres[1] : on ne
-- prend que les artistes dont le NOM est un seed de la catégorie concernée
-- (les seeds sont éditoriaux et fiables ; genres[1] est bruyant : Queen→
-- afrobeats, Marília Mendonça→rock...). Benin Hits n'a PAS de table : la
-- catégorie `Hit Benin` est servie par le pipeline seeds YT/iTunes existant.
--
-- Tables : 'artists_' + catégorie sans caractères spéciaux (lower)
--   fr-rap   -> artists_frrap   (seeds Rap Français, 238 matchs)
--   us-rap   -> artists_usrap   (seeds Rap, 152 matchs)
--   afro-rap -> artists_afrorap (seeds Afro Hip-Hop + African Hip-Hop +
--                                Afro Drill + African Drill, 15 matchs)
--   afrobeats-> artists_afrobeats (seeds Afrobeats, 151 matchs)
--   afro-hits-> artists_afrohits  (seeds Afro Hits, 151 matchs)

create or replace function public.sanitize_cat(p text) returns text
language sql immutable as $$
  select lower(regexp_replace(p, '[^a-z0-9]', '', 'g'));
$$;

-- 0) Dropper les 12 anciennes tables.
drop table if exists public.artists_hiphop;
drop table if exists public.artists_latin;
drop table if exists public.artists_rb;
drop table if exists public.artists_country;
drop table if exists public.artists_jazz;
drop table if exists public.artists_classical;
drop table if exists public.artists_electronic;
drop table if exists public.artists_reggae;
drop table if exists public.artists_kpop;
drop table if exists public.artists_rock;
drop table if exists public.artists_gospel;
drop table if exists public.artists_afrobeats;

-- 1) Créer les 5 tables v2 (structure identique à public.artists).
drop table if exists public.artists_frrap;
create table public.artists_frrap (like public.artists including all);
drop table if exists public.artists_usrap;
create table public.artists_usrap (like public.artists including all);
drop table if exists public.artists_afrorap;
create table public.artists_afrorap (like public.artists including all);
drop table if exists public.artists_afrobeats;
create table public.artists_afrobeats (like public.artists including all);
drop table if exists public.artists_afrohits;
create table public.artists_afrohits (like public.artists including all);

-- 2) Peuplement par seeds (match lower(name), distinct par nom).
insert into public.artists_frrap
select distinct on (a.name) a.*
from public.artists a
join (
  select distinct lower(unnest(artists)) seed_name
  from public.category_artist_seeds where category = 'Rap Français'
) s on lower(a.name) = s.seed_name
order by a.name, a.followers desc;

insert into public.artists_usrap
select distinct on (a.name) a.*
from public.artists a
join (
  select distinct lower(unnest(artists)) seed_name
  from public.category_artist_seeds where category = 'Rap'
) s on lower(a.name) = s.seed_name
order by a.name, a.followers desc;

insert into public.artists_afrorap
select distinct on (a.name) a.*
from public.artists a
join (
  select distinct lower(unnest(artists)) seed_name
  from public.category_artist_seeds
  where (category = 'Afro Hits' and sub in ('African Drill', 'Afro Hip-Hop'))
     or (category = 'Hip-Hop' and sub = 'African Hip-Hop')
     or (category = 'Drill' and sub = 'Afro Drill')
) s on lower(a.name) = s.seed_name
order by a.name, a.followers desc;

insert into public.artists_afrobeats
select distinct on (a.name) a.*
from public.artists a
join (
  select distinct lower(unnest(artists)) seed_name
  from public.category_artist_seeds where category = 'Afrobeats'
) s on lower(a.name) = s.seed_name
order by a.name, a.followers desc;

insert into public.artists_afrohits
select distinct on (a.name) a.*
from public.artists a
join (
  select distinct lower(unnest(artists)) seed_name
  from public.category_artist_seeds where category = 'Afro Hits'
) s on lower(a.name) = s.seed_name
order by a.name, a.followers desc;

-- 3) RLS : lecture publique (anon), écriture service_role uniquement.
do $$
declare cat text; new_table text;
begin
  foreach cat in array array['fr-rap','us-rap','afro-rap','afrobeats','afro-hits'] loop
    new_table := 'artists_' || public.sanitize_cat(cat);
    execute format('alter table public.%I enable row level security', new_table);
    execute format('drop policy if exists "read" on public.%I', new_table);
    execute format('create policy "read" on public.%I for select using (true)', new_table);
    execute format('drop policy if exists "manage" on public.%I', new_table);
    execute format('create policy "manage" on public.%I for all to service_role using (true) with check (true)', new_table);
  end loop;
end $$;

-- 4) Index popularité et nom pour un tri stable.
do $$
declare cat text; new_table text;
begin
  foreach cat in array array['fr-rap','us-rap','afro-rap','afrobeats','afro-hits'] loop
    new_table := 'artists_' || public.sanitize_cat(cat);
    execute format('create index %I on public.%I (followers desc)', new_table || '_followers_idx', new_table);
    execute format('create index %I on public.%I (lower(name))', new_table || '_name_idx', new_table);
  end loop;
end $$;

-- 5) Récapitulatif.
do $$
declare cat text; new_table text; n int;
begin
  foreach cat in array array['fr-rap','us-rap','afro-rap','afrobeats','afro-hits'] loop
    new_table := 'artists_' || public.sanitize_cat(cat);
    execute format('select count(*) from public.%I', new_table) into n;
    raise notice '% -> % artistes', new_table, n;
  end loop;
end $$;

drop function if exists public.sanitize_cat(text);