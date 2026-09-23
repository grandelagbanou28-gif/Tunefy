import 'package:muzo/models/muzo_item.dart';

/// Chat message persisted for Tunefy DJ (Hive JSON).
class DjChatMessage {
  final String id;
  final bool fromUser;
  final String text;
  final DateTime createdAt;

  /// When set, the bubble links to a generated mix page (50+ tracks…).
  final String? mixId;

  const DjChatMessage({
    required this.id,
    required this.fromUser,
    required this.text,
    required this.createdAt,
    this.mixId,
  });

  factory DjChatMessage.user(String text) => DjChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        fromUser: true,
        text: text,
        createdAt: DateTime.now(),
      );

  factory DjChatMessage.bot(String text, {String? mixId}) => DjChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        fromUser: false,
        text: text,
        createdAt: DateTime.now(),
        mixId: mixId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromUser': fromUser,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        if (mixId != null) 'mixId': mixId,
      };

  factory DjChatMessage.fromJson(Map<String, dynamic> j) => DjChatMessage(
        id: j['id'] as String? ?? '',
        fromUser: j['fromUser'] as bool? ?? false,
        text: j['text'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        mixId: j['mixId'] as String?,
      );
}

/// A generated DJ mix (full track list) persisted so the chat can open a
/// dedicated play page for 50+ songs without regenerating.
class DjGeneratedMix {
  final String id;
  final String mood;
  final String title;
  final DateTime createdAt;
  final int durationMinutes;
  final List<MuzoItem> tracks;

  const DjGeneratedMix({
    required this.id,
    required this.mood,
    required this.title,
    required this.createdAt,
    required this.durationMinutes,
    required this.tracks,
  });

  int get trackCount => tracks.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'mood': mood,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'durationMinutes': durationMinutes,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory DjGeneratedMix.fromJson(Map<String, dynamic> j) {
    final rawTracks = j['tracks'] as List? ?? const [];
    final tracks = <MuzoItem>[];
    for (final t in rawTracks) {
      if (t is Map) {
        try {
          tracks.add(MuzoItem.fromJson(Map<String, dynamic>.from(t)));
        } catch (_) {}
      }
    }
    return DjGeneratedMix(
      id: j['id'] as String? ?? '',
      mood: j['mood'] as String? ?? '',
      title: j['title'] as String? ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
          DateTime.now(),
      durationMinutes: j['durationMinutes'] as int? ?? 60,
      tracks: tracks,
    );
  }
}
