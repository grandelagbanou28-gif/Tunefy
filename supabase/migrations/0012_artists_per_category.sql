-- Tunefy Artists Catalog — 0012_artists_per_category
-- Une table PAR catégorie au lieu d'une seule table publique groupée.
-- Chaque artiste vit dans EXACTEMENT une table : celle de son genre primaire
-- (premier élément de genres[]), pour qu'un artiste n'apparaisse jamais dans
-- deux catégories différentes => aucun doublon inter-catégories à la source.
--
-- Les 12 catégories ci-dessous sont celles réellement servies par l'écran
-- HOME (lib/screens/home_screen.dart — _SearchSection : createdForYou,
-- drillMix, latinForYou, rnbSoulForYou, countryForYou, jazzForYou,
-- classicalForYou, electronicForYou, reggaeForYou, kpopForYou, afroForYou,
-- rockForYou, gospelForYou). Aucune autre catégorie ne doit exister en base.
--
-- Convention de nommage : 'artists_' + catégorie sans caractères spéciaux
-- (hip-hop -> hiphop, k-pop -> kpop, r&b -> rnb).

create or replace function public.sanitize_cat(p text) returns text
language sql immutable as $$
  select lower(regexp_replace(p, '[^a-z0-9]', '', 'g'));
$$;

-- 1) Créer les tables par catégorie (structure identique à la table artists)
--    et les peupler depuis public.artists, en ne prenant que les artistes dont
--    le genre primaire (genres[1]) est celui de la table.
do $$
declare cat text; new_table text;
begin
  foreach cat in array array[
    'afrobeats','hip-hop','latin','r&b','country','jazz',
    'classical','electronic','reggae','k-pop','rock','gospel'
  ] loop
    new_table := 'artists_' || public.sanitize_cat(cat);
    execute format('drop table if exists public.%I', new_table);
    execute format('create table public.%I (like public.artists including all)', new_table);
    execute format($sql$
      insert into public.%I
      select a.* from public.artists a
      where coalesce(a.genres[1], '') = %L
    $sql$, new_table, cat);
  end loop;
end $$;

-- 2) RLS : lecture publique (anon), écriture service_role uniquement.
do $$
declare cat text; new_table text;
begin
  foreach cat in array array[
    'afrobeats','hip-hop','latin','r&b','country','jazz',
    'classical','electronic','reggae','k-pop','rock','gospel'
  ] loop
    new_table := 'artists_' || public.sanitize_cat(cat);
    execute format('alter table public.%I enable row level security', new_table);
    execute format('drop policy if exists "read" on public.%I', new_table);
    execute format('create policy "read" on public.%I for select using (true)', new_table);
    execute format('drop policy if exists "manage" on public.%I', new_table);
    execute format('create policy "manage" on public.%I for all to service_role using (true) with check (true)', new_table);
  end loop;
end $$;

-- 3) Index popularité pour un tri stable par table.
do $$
declare cat text; new_table text;
begin
  foreach cat in array array[
    'afrobeats','hip-hop','latin','r&b','country','jazz',
    'classical','electronic','reggae','k-pop','rock','gospel'
  ] loop
    new_table := 'artists_' || public.sanitize_cat(cat);
    execute format('create index %I on public.%I (followers desc)', new_table || '_followers_idx', new_table);
    execute format('create index %I on public.%I (lower(name))', new_table || '_name_idx', new_table);
  end loop;
end $$;

-- 4) Récapitulatif : nombre d'artistes par table.
do $$
declare cat text; new_table text; n int;
begin
  foreach cat in array array[
    'afrobeats','hip-hop','latin','r&b','country','jazz',
    'classical','electronic','reggae','k-pop','rock','gospel'
  ] loop
    new_table := 'artists_' || public.sanitize_cat(cat);
    execute format('select count(*) from public.%I', new_table) into n;
    raise notice '% -> % artistes', new_table, n;
  end loop;
end $$;

drop function if exists public.sanitize_cat(text);