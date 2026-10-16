/// Static, bundled artwork for every "Browse All" category.
///
/// The app no longer fetches category banners from the network — each category
/// ships with a real bundled cover so the banner is instant, offline-safe and
/// always on-brand. The map is keyed by the category `query` (lowercase) with
/// the display `title` as a fallback key.
///
/// Every entry points at its OWN dedicated cover in `assets/covers/`. They used
/// to be recycled from unrelated Spotify mix artwork (Drake-Mix, UTOPIA,
/// 2023_wrapped…), which is why an "Amapiano" or "Musique Arabe" category showed
/// a picture that had nothing to do with it.
library;

const String _covers = "assets/covers/";

/// query (lowercase) -> bundled asset path.
const Map<String, String> _assetsByQuery = {
  "pop": "${_covers}pop.jpg",
  "hip hop": "${_covers}hiphop.jpg",
  "rock": "${_covers}rock.jpg",
  "r&b": "${_covers}rnb.jpg",
  "latin": "${_covers}latin.jpg",
  "country": "${_covers}country.jpg",
  "jazz": "${_covers}jazz.jpg",
  "classical": "${_covers}classical.jpg",
  "electronic": "${_covers}electronic.jpg",
  "reggae": "${_covers}reggae.jpg",
  "blues": "${_covers}blues.jpg",
  "metal": "${_covers}metal.jpg",
  "folk acoustic": "${_covers}folkacoustic.jpg",
  "soul": "${_covers}soul.jpg",
  "funk": "${_covers}funk.jpg",
  "gospel": "${_covers}gospel.jpg",
  "rap": "${_covers}rap.jpg",
  "k-pop": "${_covers}kpop.jpg",
  "indie": "${_covers}indie.jpg",
  "afro hits": "${_covers}afrohits.jpg",
  "afrobeats": "${_covers}afrobeats.jpg",
  "caribbean": "${_covers}caribbean.jpg",
  "desi hits": "${_covers}desi.jpg",
  "house music": "${_covers}house.jpg",
  "lofi beats": "${_covers}lofibeats.jpg",
  "party": "${_covers}party.jpg",
  "dance": "${_covers}party.jpg",
  "romantic love songs": "${_covers}romance.jpg",
  "love": "${_covers}romance.jpg",
  "workout": "${_covers}workout.jpg",
  "focus": "${_covers}focus.jpg",
  "sleep": "${_covers}sleep.jpg",
  "meditation": "${_covers}meditation.jpg",
  "comedy": "${_covers}comedy.jpg",
  "news": "${_covers}newspolitics.jpg",
  "podcast": "${_covers}podcasts.jpg",
  "podcasts": "${_covers}podcasts.jpg",
  "chill mood": "${_covers}chill.jpg",
  "mood": "${_covers}mood.jpg",
  "chill": "${_covers}chill.jpg",
  "oldies": "${_covers}decades.jpg",
  "new release": "${_covers}newreleases.jpg",
  "new releases": "${_covers}newreleases.jpg",
  "top hits": "${_covers}charts.jpg",
  "chill mix": "${_covers}chill.jpg",
  "live": "${_covers}party.jpg",
  "benin hits": "${_covers}benin.jpg",
  "amapiano": "${_covers}amapiano.jpg",
  "bande originale": "${_covers}bandeoriginale.jpg",
  "dancehall": "${_covers}dancehall.jpg",
  "musique arabe": "${_covers}musiquearabe.jpg",
  "rumba congolaise": "${_covers}rumbacongolaise.jpg",
  "drill": "${_covers}drill.jpg",
  "rap francais": "${_covers}rapfrancais.jpg",
  "chanson francaise": "${_covers}chanson.jpg",
  "new artists": "${_covers}newreleases.jpg",
  "hit benin": "${_covers}benin.jpg",
};

/// Display title (lowercase) -> bundled asset path.
const Map<String, String> _assetsByTitle = {
  "pop": "${_covers}pop.jpg",
  "hip-hop": "${_covers}hiphop.jpg",
  "rock": "${_covers}rock.jpg",
  "r&b": "${_covers}rnb.jpg",
  "latin": "${_covers}latin.jpg",
  "country": "${_covers}country.jpg",
  "jazz": "${_covers}jazz.jpg",
  "classical": "${_covers}classical.jpg",
  "electronic": "${_covers}electronic.jpg",
  "reggae": "${_covers}reggae.jpg",
  "soul": "${_covers}soul.jpg",
  "funk": "${_covers}funk.jpg",
  "gospel": "${_covers}gospel.jpg",
  "rap": "${_covers}rap.jpg",
  "k-pop": "${_covers}kpop.jpg",
  "indie": "${_covers}indie.jpg",
  "afro hits": "${_covers}afrohits.jpg",
  "afrobeats": "${_covers}afrobeats.jpg",
  "caribbean": "${_covers}caribbean.jpg",
  "desi": "${_covers}desi.jpg",
  "house": "${_covers}house.jpg",
  "lo-fi beats": "${_covers}lofibeats.jpg",
  "party": "${_covers}party.jpg",
  "romance": "${_covers}romance.jpg",
  "workout": "${_covers}workout.jpg",
  "focus": "${_covers}focus.jpg",
  "sleep": "${_covers}sleep.jpg",
  "meditation": "${_covers}meditation.jpg",
  "comedy": "${_covers}comedy.jpg",
  "news & politics": "${_covers}newspolitics.jpg",
  "podcasts": "${_covers}podcasts.jpg",
  "mood": "${_covers}mood.jpg",
  "chill": "${_covers}chill.jpg",
  "decades": "${_covers}decades.jpg",
  "new releases": "${_covers}newreleases.jpg",
  "charts": "${_covers}charts.jpg",
  "made for you": "${_covers}madeforyou.jpg",
  "trending": "${_covers}trending.jpg",
  "hit benin": "${_covers}benin.jpg",
  "amapiano": "${_covers}amapiano.jpg",
  "bande originale": "${_covers}bandeoriginale.jpg",
  "dancehall": "${_covers}dancehall.jpg",
  "musique arabe": "${_covers}musiquearabe.jpg",
  "rumba congolaise": "${_covers}rumbacongolaise.jpg",
  "drill": "${_covers}drill.jpg",
  "rap fran\u00e7ais": "${_covers}rapfrancais.jpg",
  "chansons": "${_covers}chansons.jpg",
  "blues": "${_covers}blues.jpg",
  "metal": "${_covers}metal.jpg",
  "folk & acoustic": "${_covers}folkacoustic.jpg",
};

/// Returns the bundled asset path for a category, or null if none matches.
String? categoryAsset(String query, String title) {
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty && _assetsByQuery.containsKey(q)) return _assetsByQuery[q];
  final t = title.trim().toLowerCase();
  if (t.isNotEmpty && _assetsByTitle.containsKey(t)) return _assetsByTitle[t];
  return null;
}
