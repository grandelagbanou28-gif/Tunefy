-- Tunefy — catalogue statique de contenu par sous-catégorie.
--
-- Couche de secours pour les sous-catégories qui ne produisent jamais (ou
-- trop peu) de contenu vérifié en direct (ex : "Hits Bénin > Benin Gospel").
-- Chaque ligne est une PISTE RÉELLE curatée manuellement :
--   - title     : titre réel de la chanson
--   - artist    : nom réel de l'artiste
--   - video_id  : identifiant YouTube RÉEL de la vidéo (jamais inventé)
--   - thumbnail : URL facultative (l'app génère i.ytimg.com/vi/<id>/hqdefault
--                 quand absente)
-- La table est en lecture seule pour le rôle anonyme (RLS select using true) :
-- l'app ne fait que LIRE ; l'écriture passe par le Dashboard (SQL Editor).
--
-- Insertion (SQL Editor) :
--   insert into public.category_content (category, sub, title, artist, video_id, sort)
--   values ('Hits Bénin', 'Benin Gospel', '<titre>', '<artiste>', '<video_id>', 0)
--   on conflict (category, sub, video_id) do nothing;

create table if not exists public.category_content (
  id         uuid primary key default gen_random_uuid(),
  category   text not null,
  sub        text not null,
  title      text not null,
  artist     text not null,
  video_id   text not null,
  thumbnail  text,
  sort       integer not null default 0,
  created_at timestamptz not null default now()
);

create unique index if not exists category_content_unique_video
  on public.category_content (category, sub, video_id);

create index if not exists category_content_lookup
  on public.category_content (category, sub);

alter table public.category_content enable row level security;

drop policy if exists "category_content_anon_read" on public.category_content;
create policy "category_content_anon_read"
  on public.category_content
  for select
  using (true);