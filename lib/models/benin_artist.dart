/// A verified artist / group row from the Supabase `benin_artists`
/// catalog. All fields mirror the Postgres columns; unknown values are null.
class BeninArtist {
  final String name;
  final String type;
  final String? country;
  final String? countryCode;
  final List<String> categories;
  final List<String> languages;
  final bool verified;
  final String? imageUrl;
  final String? officialWebsite;
  final String? spotifyId;
  final String? appleMusicId;
  final String? youtubeChannelId;
  final String? sourceUrl;

  BeninArtist({
    required this.name,
    this.type = 'artist',
    this.country,
    this.countryCode,
    this.categories = const [],
    this.languages = const [],
    this.verified = false,
    this.imageUrl,
    this.officialWebsite,
    this.spotifyId,
    this.appleMusicId,
    this.youtubeChannelId,
    this.sourceUrl,
  });

  factory BeninArtist.fromJson(Map<String, dynamic> json) {
    String? s(String key) => json[key]?.toString();
    List<String> arr(String key) {
      final v = json[key];
      if (v is List) return v.map((e) => e.toString()).toList();
      return const [];
    }

    return BeninArtist(
      name: s('name') ?? '',
      type: s('type') ?? 'artist',
      country: s('country'),
      countryCode: s('country_code'),
      categories: arr('categories'),
      languages: arr('languages'),
      verified: json['verified'] == true,
      imageUrl: s('image_url'),
      officialWebsite: s('official_website'),
      spotifyId: s('spotify_id'),
      appleMusicId: s('apple_music_id'),
      youtubeChannelId: s('youtube_channel_id'),
      sourceUrl: s('source_url'),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'country': country,
        'country_code': countryCode,
        'categories': categories,
        'languages': languages,
        'verified': verified,
        'image_url': imageUrl,
        'official_website': officialWebsite,
        'spotify_id': spotifyId,
        'apple_music_id': appleMusicId,
        'youtube_channel_id': youtubeChannelId,
        'source_url': sourceUrl,
      };
}
