import 'package:muzo/models/muzo_item.dart';

/// One Blend member (one device/user), shown as "added by" on tracks.
class BlendMember {
  final String uid;
  final String name;

  const BlendMember({required this.uid, required this.name});

  factory BlendMember.fromJson(Map<String, dynamic> j) => BlendMember(
        uid: j['uid']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {'uid': uid, 'name': name};
}

/// One track inside a Blend, credited to the member who added it.
class BlendTrack {
  final MuzoItem song;
  final String addedByUid;
  final String addedByName;
  final String addedAt;

  const BlendTrack({
    required this.song,
    required this.addedByUid,
    required this.addedByName,
    required this.addedAt,
  });

  factory BlendTrack.fromJson(Map<String, dynamic> j) => BlendTrack(
        song: MuzoItem.fromJson(Map<String, dynamic>.from(j['song'] as Map)),
        addedByUid: j['added_by_uid']?.toString() ?? '',
        addedByName: j['added_by_name']?.toString() ?? '',
        addedAt: j['added_at']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'song': song.toJson(),
        'added_by_uid': addedByUid,
        'added_by_name': addedByName,
        'added_at': addedAt,
      };
}

/// A shared Blend playlist: one join code, several members, one merged
/// track list. Last-write-wins on the document (same trade-off as the
/// per-user playlists table).
class Blend {
  final String code;
  final String name;
  final List<BlendMember> members;
  final List<BlendTrack> tracks;

  const Blend({
    required this.code,
    required this.name,
    this.members = const [],
    this.tracks = const [],
  });

  factory Blend.fromRow(String code, Map<String, dynamic> row) {
    final data = row['data'];
    final m = data is Map ? Map<String, dynamic>.from(data) : {};
    return Blend(
      code: code,
      name: (row['name'] ?? m['name'] ?? 'Blend').toString(),
      members: ((m['members'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => BlendMember.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      tracks: ((m['tracks'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => BlendTrack.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'members': members.map((e) => e.toJson()).toList(),
        'tracks': tracks.map((e) => e.toJson()).toList(),
      };

  /// All tracks as plain songs, in blend order.
  List<MuzoItem> get songs => tracks.map((t) => t.song).toList();
}
