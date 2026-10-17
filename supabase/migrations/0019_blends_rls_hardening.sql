-- 0019_blends_rls_hardening.sql
-- Durcit la RLS des Blends : exige une identité authentifiée Supabase en
-- lecture ET écriture. Le design "le code est l'invite" est préservé (tout
-- membre détenant le code lit et contribue toujours), mais une clé anon brute
-- sans session ne peut plus toucher la table — chaque accès devient
-- attribuable à un uid + limitable au niveau passerelle.
--
-- RISQUE RÉSIDUEL ( assumé ) : avec `using (true)` en select, tout appareil
-- *authentifié* peut toujours énumérer tous les blends (le code est la clé
-- primaire et la RLS ne peut pas exiger "preuve de connaissance du code").
-- Les données d'un blend sont peu sensibles (playlists partagées), donc on
-- l'accepte. Empêcher totalement l'énumération demanderait le code haché au
-- repos ou un petit backend validant le code — pas de la RLS.
--
-- -- À exécuter dans le SQL Editor Supabase (Dashboard → SQL Editor) --
-- Idempotent: safe to run more than once.

-- Lecture : authentifié uniquement.
drop policy if exists "blends_read" on public.blends;
create policy "blends_read" on public.blends
  to authenticated
  for select using (true);

-- Rejoindre (création) : authentifié uniquement.
drop policy if exists "blends_write" on public.blends;
create policy "blends_write" on public.blends
  to authenticated
  for insert with check (true);

-- Contribuer (mise à jour) : authentifié uniquement.
drop policy if exists "blends_update" on public.blends;
create policy "blends_update" on public.blends
  to authenticated
  for update using (true) with check (true);
