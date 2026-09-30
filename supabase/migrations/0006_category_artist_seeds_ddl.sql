-- Tunefy — table publique des artistes curatés par catégorie/sous-catégorie
-- (Mood, Sleep, Focus, Workout, Decades, Romance, Made For You...).
-- L'app la lit en REST (anon) avec cache Hive et repli sur les seeds locaux.
-- DDL seul : le seed est envoyé ensuite via l'API (service_role).

create table if not exists public.category_artist_seeds (
  category text not null,
  sub      text not null,
  artists  text[] not null default '{}',
  primary key (category, sub)
);

alter table public.category_artist_seeds enable row level security;

drop policy if exists "category_artist_seeds_read" on public.category_artist_seeds;
create policy "category_artist_seeds_read"
  on public.category_artist_seeds
  for select
  using (true);

drop policy if exists "category_artist_seeds_manage" on public.category_artist_seeds;
create policy "category_artist_seeds_manage"
  on public.category_artist_seeds
  for all
  to service_role
  using (true)
  with check (true);

create index if not exists category_artist_seeds_category_idx
  on public.category_artist_seeds (category);