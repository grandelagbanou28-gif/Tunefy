/// Curated list of popular artists of 2026, grouped by month (January → the
/// current month). Each month holds at least 7 artists so the home screen can
/// render one artist row per month.
///
/// Editorial: edit freely to match the real monthly charts. Items are just
/// names; the artist page is resolved from the name at tap time.
library;

const Map<String, List<String>> popularArtists2026 = {
  // Janvier 2026
  'janvier': [
    'Bad Bunny',
    'Taylor Swift',
    'Billie Eilish',
    'Kendrick Lamar',
    'SZA',
    'Ariana Grande',
    'The Weeknd',
    'Sabrina Carpenter',
  ],
  // Février 2026
  'février': [
    'Taylor Swift',
    'Playboi Carti',
    'Lola Young',
    'Chappell Roan',
    'Doja Cat',
    'Travis Scott',
    'Beyoncé',
    'Gazo',
  ],
  // Mars 2026
  'mars': [
    'Kendrick Lamar',
    'Bad Bunny',
    'SZA',
    'Lil Baby',
    'Drake',
    'Rosalía',
    'Central Cee',
    'Billie Eilish',
  ],
  // Avril 2026
  'avril': [
    'The Weeknd',
    'Ariana Grande',
    'Jennie',
    'A\$AP Rocky',
    'Cardi B',
    'Post Malone',
    'Wizkid',
    'Sabrina Carpenter',
  ],
  // Mai 2026
  'mai': [
    'Taylor Swift',
    'Doechii',
    'Sexyy Red',
    'Nicki Minaj',
    'Rema',
    'Tyla',
    'Ed Sheeran',
    'Future',
  ],
  // Juin 2026
  'juin': [
    'Drake',
    'Don Toliver',
    'Anitta',
    'Shakira',
    'Rihanna',
    'Jung Kook',
    'Sofiane Pamart',
    'Lil Uzi Vert',
  ],
  // Juillet 2026
  'juillet': [
    'Bad Bunny',
    'Karol G',
    'Taylor Swift',
    'Billie Eilish',
    'Chris Brown',
    'Maluma',
    'Tems',
    'Peso Pluma',
  ],
  // Août 2026
  'août': [
    'Kendrick Lamar',
    'SZA',
    'Ariana Grande',
    'The Weeknd',
    'Burna Boy',
    'Ruto Show',
    'Ayra Starr',
    'Sabrina Carpenter',
  ],
  // Septembre 2026
  'septembre': [
    'Taylor Swift',
    'Bad Bunny',
    'Billie Eilish',
    'Drake',
    'Central Cee',
    'Karol G',
    'Tyla',
    'Lila Iké',
  ],
};

/// French month keys, ordered January → December.
const List<String> _monthKeys = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// Returns the month key (e.g. 'septembre') for a given date.
String monthKeyFor(DateTime now) =>
    _monthKeys[(now.month - 1).clamp(0, _monthKeys.length - 1)];

/// The list of popular artists for a given date, based on its month. Falls back
/// to the current-month list's nearest populated month so there are always at
/// least 7 artists.
List<String> popularArtistsFor(DateTime now) {
  final key = monthKeyFor(now);
  final direct = popularArtists2026[key];
  if (direct != null && direct.length >= 7) return direct;
  // Fallback: use whatever month is populated before/at [now].
  final index = _monthKeys.indexOf(key);
  for (int i = index; i >= 0; i--) {
    final list = popularArtists2026[_monthKeys[i]];
    if (list != null && list.length >= 7) return list;
  }
  return popularArtists2026['janvier'] ?? const <String>[];
}
