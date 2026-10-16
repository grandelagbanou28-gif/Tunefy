/// Curated fallback "fresh releases" with **explicit release dates**.
///
/// Entries older than 7 days are dropped at runtime — this list never shows
/// stale titles. Prefer live dated sources (Deezer artist albums, iTunes RSS,
/// MusicBrainz date range); curated only seeds edge cases when APIs are thin.
library;

class CuratedRelease {
  final String artist;
  final String title;
  final String? event;
  final int year;
  final int month;
  final int day;

  const CuratedRelease({
    required this.artist,
    required this.title,
    required this.year,
    required this.month,
    required this.day,
    this.event,
  });

  /// Device-clock release day (local midnight).
  DateTime get releasedAt => DateTime(year, month, day);
}

/// Web-verified releases (checked 2026-09-24 against Billboard / Paste /
/// HitsCulture / Just Music / Official Charts / press releases).
/// [releasedAt] is the source of truth for the shelf window on the device clock.
const List<CuratedRelease> curatedNewReleases2026 = [
  // ─── Vendredi 18/09/2026 (New Music Friday) ───
  // Rumba / Afrique de l'Ouest
  CuratedRelease(
    artist: 'Fally Ipupa',
    title: 'XX : Délirium',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  // Seyi Vibez SWAGUU — Apple/Spotify 17/09, wide coverage 18/09
  CuratedRelease(
    artist: 'Seyi Vibez',
    title: 'Swaguu',
    year: 2026,
    month: 9,
    day: 17,
    event: 'album',
  ),
  // Rap FR / slam
  CuratedRelease(
    artist: 'Grand Corps Malade',
    title: 'Voir la mer',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Luther',
    title: 'shelf',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Zamdane',
    title: 'Akira',
    year: 2026,
    month: 9,
    day: 21,
    event: 'single',
  ),
  // Tiakola — teaser WpointM (album 25/09)
  CuratedRelease(
    artist: 'Tiakola',
    title: 'Caméléon',
    year: 2026,
    month: 9,
    day: 22,
    event: 'single',
  ),
  // Afrobeats — Oh No is 11/09 (outside 7d); kept accurate for 14d shelf
  CuratedRelease(
    artist: 'Rema',
    title: 'Oh No',
    year: 2026,
    month: 9,
    day: 11,
    event: 'single',
  ),
  // Rap US
  CuratedRelease(
    artist: 'AZ Chike',
    title: 'No Rest for The Wicked',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Rakim, Kurupt & Masta Killa',
    title: 'The Godbody LP',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  // Pop / rock
  CuratedRelease(
    artist: 'Beck',
    title: 'Ride Lonesome',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Carly Rae Jepsen',
    title: 'Day and Night',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Miley Cyrus',
    title: 'Bass Persuades',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  // Gospel / worship
  CuratedRelease(
    artist: 'for KING & COUNTRY',
    title: 'the most beautiful colours',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Cory Asbury',
    title: 'Outsing The Angels',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Anthony Brown & group therAPy',
    title: 'Full Disclosure',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Franni Cash',
    title: 'Here I Am',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  // Singles FR / Afrique — 18/09
  CuratedRelease(
    artist: 'Kebero',
    title: 'Jamais',
    year: 2026,
    month: 9,
    day: 18,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Julaï',
    title: 'Tehfouf',
    year: 2026,
    month: 9,
    day: 18,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Roseline Layo & Fatoumata Diawara',
    title: "DEN'BA",
    year: 2026,
    month: 9,
    day: 18,
    event: 'single',
  ),
  // Pop / R&B / hip-hop singles — 17–18/09
  CuratedRelease(
    artist: 'Anderson .Paak & Cordae',
    title: 'A Good Day',
    year: 2026,
    month: 9,
    day: 18,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Teddy Swims',
    title: 'Perfect Man',
    year: 2026,
    month: 9,
    day: 18,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Travis Scott',
    title: 'RHYNO',
    year: 2026,
    month: 9,
    day: 17,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Dominic Fike',
    title: 'Small Town',
    year: 2026,
    month: 9,
    day: 18,
    event: 'single',
  ),
  // Albums pop / R&B — 18/09
  CuratedRelease(
    artist: 'Tove Lo',
    title: 'Estrus',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'beabadoobee',
    title: 'Pylon',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Neil Young & The Chrome Hearts',
    title: 'Second Song',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Chaka Khan',
    title: 'Chakzilla',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Lizzy McAlpine',
    title: 'Angel',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Daley',
    title: 'Strange Nature',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Kareen Lomax',
    title: 'NAJI',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  // Extra 18/09 albums (Billboard / Paste / Partisan / Press)
  CuratedRelease(
    artist: 'Ezra Collective',
    title: 'Here Because of Hope',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Orville Peck',
    title: 'Mule',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Rhiannon Giddens',
    title: 'Hope Is the Thing with Feathers',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Slow Pulp',
    title: 'Melodie',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Hiba Tawaji & Ibrahim Maalouf',
    title: 'À la française',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  // NG / afro albums 18/09 (press)
  CuratedRelease(
    artist: 'Dremo',
    title: 'Man2Man',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Erigga',
    title: 'G.O.A.T',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Lojay & Sarz',
    title: 'LV N ATTN',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  CuratedRelease(
    artist: 'Victor AD',
    title: 'Realness Over Hype',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),
  // MC Solaar 5ème As reissue — 18/09 (rap FR)
  CuratedRelease(
    artist: 'MC Solaar',
    title: '5ème As',
    year: 2026,
    month: 9,
    day: 18,
    event: 'album',
  ),

  // ─── Semaine 19–24/09/2026 ───
  CuratedRelease(
    artist: 'Daguerre',
    title: 'Corps Voyou',
    year: 2026,
    month: 9,
    day: 21,
    event: 'album',
  ),
  // Afro / NG singles mid-week
  CuratedRelease(
    artist: 'Phyno, Burna Boy & M.I Abaga',
    title: 'Link Up',
    year: 2026,
    month: 9,
    day: 20,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Blaqbonez & Asake',
    title: 'Chanel',
    year: 2026,
    month: 9,
    day: 21,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Black Sherif & AratheJay',
    title: 'Forever',
    year: 2026,
    month: 9,
    day: 21,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Fireboy DML & Masicka',
    title: 'CLAAT!',
    year: 2026,
    month: 9,
    day: 21,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Nao & Adekunle Gold',
    title: 'Antidote',
    year: 2026,
    month: 9,
    day: 21,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Shoday & MAGIXX',
    title: 'Che',
    year: 2026,
    month: 9,
    day: 22,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Fireboy DML, Jazzwrld & Thukuthela',
    title: 'Imali',
    year: 2026,
    month: 9,
    day: 23,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Frenna, Wizkid & Odeal',
    title: 'Coca Body',
    year: 2026,
    month: 9,
    day: 23,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Blaqbonez, Valiant & The Kazez',
    title: 'Bizzy Body',
    year: 2026,
    month: 9,
    day: 23,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Chocolate City, Blaqbonez, Major AJ & Noon Dave',
    title: 'Tonight',
    year: 2026,
    month: 9,
    day: 23,
    event: 'single',
  ),
  CuratedRelease(
    artist: 'Balloranking & L.A.X',
    title: 'Aje',
    year: 2026,
    month: 9,
    day: 23,
    event: 'single',
  ),
];

/// True when [c] is still inside the device-clock [window] ending now.
bool curatedIsFresh(CuratedRelease c, {required Duration window}) {
  final now = DateTime.now();
  return !c.releasedAt.isAfter(now) &&
      !c.releasedAt.isBefore(now.subtract(window));
}

/// Artist name used to resolve the artist page for a [CuratedRelease];
/// normalises an entity name kept simple (no smart quotes) to how the artist
/// page is likely labelled.
String curatedArtistFor(CuratedRelease c) => c.artist;

/// Artists in this list that are NOT rap / R&B / afro. The web-verified
/// releases were collected across every genre, but the home shelves only ever
/// promise rap FR, rap US and afro — so anything else is dropped there.
const Set<String> _nonUrbanCuratedArtists = <String>{
  'beck',
  'carly rae jepsen',
  'chaka khan',
  'cory asbury',
  'anthony brown',
  'for king & country',
  'ezra collective',
  'orville peck',
  'neil young',
  'miley cyrus',
  'tove lo',
  'lizzy mcalpine',
  'teddy swims',
  'beabadoobee',
  'slow pulp',
  'rhiannon giddens',
  'dominic fike',
  'hiba tawaji',
  'kareen lomax',
  'daley',
  'kebero',
  'franni cash',
};

/// True when this release belongs to the genres the app serves (rap FR/US,
/// R&B, afro). Feature credits are checked as a whole, so "Fireboy DML &
/// Masicka" stays in.
bool isUrbanOrAfroRelease(CuratedRelease c) {
  final artist = c.artist.toLowerCase();
  return !_nonUrbanCuratedArtists.any(artist.contains);
}