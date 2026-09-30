/// Normalized concert event — same shape Freedify uses after Ticketmaster /
/// SeatGeek mapping, so the UI and cache stay provider-agnostic.
class ConcertEvent {
  final String id;
  final String name;
  final String artist;
  final String venue;
  final String city;
  final String state;
  final String country;
  final DateTime? date;
  final String time;
  final String ticketUrl;
  final double? priceMin;
  final double? priceMax;
  final String currency;
  final String image;
  final String source;

  const ConcertEvent({
    required this.id,
    required this.name,
    required this.artist,
    required this.venue,
    required this.city,
    this.state = '',
    this.country = '',
    this.date,
    this.time = '',
    this.ticketUrl = '',
    this.priceMin,
    this.priceMax,
    this.currency = '',
    this.image = '',
    this.source = '',
  });

  bool get isUpcoming {
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !date!.isBefore(today);
  }

  String get locationLabel {
    final parts = <String>[
      if (venue.isNotEmpty) venue,
      if (city.isNotEmpty) city,
      if (state.isNotEmpty) state,
    ];
    return parts.join(', ');
  }

  String get priceLabel {
    final cur = currency.isEmpty ? '' : '$currency ';
    if (priceMin != null && priceMax != null && priceMax! > priceMin!) {
      return '$cur${priceMin!.toStringAsFixed(0)} – ${priceMax!.toStringAsFixed(0)}';
    }
    if (priceMin != null) return '$cur${priceMin!.toStringAsFixed(0)}';
    if (priceMax != null) return '$cur${priceMax!.toStringAsFixed(0)}';
    return '';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'artist': artist,
        'venue': venue,
        'city': city,
        'state': state,
        'country': country,
        'date': date?.toIso8601String(),
        'time': time,
        'ticket_url': ticketUrl,
        'price_min': priceMin,
        'price_max': priceMax,
        'currency': currency,
        'image': image,
        'source': source,
      };

  factory ConcertEvent.fromJson(Map<String, dynamic> j) {
    DateTime? parseDate(Object? raw) {
      if (raw == null) return null;
      final s = raw.toString().trim();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s) ??
          DateTime.tryParse('${s}T00:00:00') ??
          DateTime.tryParse(s.split('T').first);
    }

    double? asDouble(Object? v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return ConcertEvent(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      artist: j['artist']?.toString() ?? '',
      venue: j['venue']?.toString() ?? '',
      city: j['city']?.toString() ?? '',
      state: j['state']?.toString() ?? '',
      country: j['country']?.toString() ?? '',
      date: parseDate(j['date']),
      time: j['time']?.toString() ?? '',
      ticketUrl: (j['ticket_url'] ?? j['ticketUrl'] ?? '').toString(),
      priceMin: asDouble(j['price_min'] ?? j['priceMin']),
      priceMax: asDouble(j['price_max'] ?? j['priceMax']),
      currency: j['currency']?.toString() ?? '',
      image: j['image']?.toString() ?? '',
      source: j['source']?.toString() ?? '',
    );
  }
}
