import 'package:muzo/models/muzo_item.dart';

/// True when [item] is a watchable video rather than an audio track.
bool isWatchableVideo(MuzoItem item) =>
    item.resultType.toLowerCase() == 'video' &&
    (item.videoId ?? '').isNotEmpty;

/// `m:ss` for a video result, or an empty string when the duration is unknown.
String formatVideoDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}
