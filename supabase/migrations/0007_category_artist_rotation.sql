-- Tunefy — rotation automatique des artistes curatés toutes les 72 heures.
--
-- L'app n'affiche que le TOP 6 de chaque liste (seedsForSubCategory -> take(6)).
-- Cette migration ajoute une rotation DÉTERMINISTE de l'ordre de `artists` :
-- toutes les 3 jours, chaque sous-catégorie voit un nouveau "top 6", sans jamais
-- modifier les pools exhaustifs (aucun nom perdu, juste l'ordre qui tourne).
--
-- Conception :
--  * one run par période de 72h (fonction idempotente, auto-correctrice)
--  * état conservé dans category_artist_rotation_state (dernière période traitée)
--  * SECURITY DEFINER pour contourner la RLS (comme la policy service_role)
--  * planification pg_cron : quotidienne à 03:03 ; la fonction ne tourne
--    effectivement qu'au passage d'un palier de 3 jours.

create extension if not exists pg_cron;

create table if not exists public.category_artist_rotation_state (
  rotation_key text primary key,
  last_period  bigint not null
);

create or replace function public.rotate_category_artist_seeds()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  p        bigint;      -- période courante (une période = 72h)
  key_lbl  text := 'default';
  row_     record;
  n        integer;
  amount   integer;
begin
  -- Ordinal de la période de 3 jours en cours depuis l'epoch.
  p := floor(extract(epoch from now()) / 86400.0 / 3)::bigint;

  -- Idempotent : si la période courante a déjà été traitée, on ne fait rien.
  if exists (
    select 1 from public.category_artist_rotation_state
    where rotation_key = key_lbl and last_period >= p
  ) then
    return;
  end if;

  for row_ in select category, sub, artists from public.category_artist_seeds loop
    n := cardinality(row_.artists);
    continue when n is null or n = 0;

    -- Décale l'ordre d'autant de positions que de périodes non traitées.
    amount := (((p - coalesce(
        (select last_period from public.category_artist_rotation_state
          where rotation_key = key_lbl), p)) % n) + n) % n;

    if amount <> 0 then
      update public.category_artist_seeds
         set artists = (
               select array_agg(e)
                 from unnest(
                   row_.artists[amount + 1 : n] || row_.artists[1 : amount]
                 ) e
             )
       where category = row_.category and sub = row_.sub;
    end if;
  end loop;

  insert into public.category_artist_rotation_state (rotation_key, last_period)
  values (key_lbl, p)
  on conflict (rotation_key) do update set last_period = excluded.last_period;
end;
$$;

-- Planification quotidienne ; le modulo 3 dans la fonction limite la rotation
-- réelle à un rythme de 72 heures (job "inutile" les autres jours, quasi gratuit).
select cron.unschedule('rotate-category-artists')
where exists (select 1 from cron.job where jobname = 'rotate-category-artists');

select cron.schedule(
  'rotate-category-artists',
  '3 3 * * *',
  'select public.rotate_category_artist_seeds();'
);

-- Initialisation : marque la période courante comme traitée (aucune rotation
-- immédiate ; la première rotation interviendra au prochain palier de 3 jours).
insert into public.category_artist_rotation_state (rotation_key, last_period)
values ('default', floor(extract(epoch from now()) / 86400.0 / 3)::bigint)
on conflict (rotation_key) do nothing;

-- Force manuelle pour VÉRIFIER immédiatement (décale d'une période, puis
-- maj l'état pour ne tourner à nouveau qu'au prochain palier) :
--   update public.category_artist_rotation_state set last_period = last_period - 1;
--   select public.rotate_category_artist_seeds();
-- Pour réinitialiser l'ordre d'origine (seeds du fichier Dart) : re-upsert puis
--   truncate public.category_artist_rotation_state;
--   select public.rotate_category_artist_seeds();