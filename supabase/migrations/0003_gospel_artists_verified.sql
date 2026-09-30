-- Tunefy Gospel catalog — 0003_gospel_artists_verified.sql
-- Batch 2, issu d'une recherche sources vérifiées (Music In Africa, Kophis Music,
-- Un Chant Nouveau, Wikipedia, l-frii, Soundcharts CI). Zéro donnée inventée.
-- Idempotent : relançable sans doublon (unique index lower(name)).

insert into public.gospel_artists
  (name, type, country, country_code, categories, languages, verified, source_url, last_verified)
values
-- 🇧🇯 BÉNIN — source : Music In Africa « Les femmes dans la musique béninoise »
('Dona Chanvoedou', 'artist', 'Bénin', 'BJ', '{"Gospel Urbain","Afro-Gospel"}', '{Fr}', true,
 'https://www.musicinafrica.net/fr/magazine/les-femmes-dans-la-musique-beninoise/', '2026-08-29T04:52:57Z'),
('Joyce Mambo', 'artist', 'Bénin', 'BJ', '{"Worship & Praise"}', '{Fr}', false,
 'https://www.musicinafrica.net/fr/magazine/les-femmes-dans-la-musique-beninoise/', NULL),
('Will Honor', 'artist', 'Bénin', 'BJ', '{"Worship & Praise"}', '{Fr}', false,
 'https://www.musicinafrica.net/fr/magazine/les-femmes-dans-la-musique-beninoise/', NULL),

-- 🇨🇮 CÔTE D'IVOIRE
('Schékina', 'group', 'Côte d''Ivoire', 'CI', '{"Worship & Praise","Ensemble"}', '{Fr}', true,
 'https://www.musicinafrica.net/fr/node/8347', '2026-08-29T04:52:57Z'),
('B-Right', 'artist', 'Côte d''Ivoire', 'CI', '{"Afro-Gospel","Rap"}', '{Fr}', true,
 'https://un-chant-nouveau.com/artist/b-right/', '2026-08-29T04:52:57Z'),
('All For Jesus', 'group', 'Côte d''Ivoire', 'CI', '{"Afro-Gospel","Rap"}', '{Fr}', true,
 'https://kophismusic.com/nos-artistes/all-for-jesus/', '2026-08-29T04:52:57Z'),
('Mr Potego', 'artist', 'Côte d''Ivoire', 'CI', '{"Afro-Gospel","Urban"}', '{Fr}', true,
 'https://kophismusic.com/nos-artistes/mr-potego/', '2026-08-29T04:52:57Z'),
('Indira', 'artist', 'Côte d''Ivoire', 'CI', '{"Afro-Gospel","Urban"}', '{Fr}', false,
 'https://soundcharts.com/en/songs/spotify-streams/country/c-te-d-ivoire/genre/religious', NULL),
('Serviteur Pierre', 'artist', 'Côte d''Ivoire', 'CI', '{"Afro-Gospel","Rap"}', '{Fr}', false,
 'https://l-frii.com/disciple-dans-la-ville-nouvel-album-de-ks-bloom/', NULL),

-- 🇧🇪 BELGIQUE (diaspora congolaise) — gospel rap francophone
('David Okit', 'artist', 'Belgique', 'BE', '{"Afro-Gospel","Urban","Rap"}', '{Fr}', true,
 'https://fr.wikipedia.org/wiki/David_Okit', '2026-08-29T04:52:57Z')
on conflict ((lower(name))) do nothing;