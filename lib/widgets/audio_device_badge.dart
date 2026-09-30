import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/providers/audio_device_provider.dart';
import 'package:muzo/services/audio_device_service.dart';

/// Headphone glyph that shows up on the mini player and the now playing
/// screen as soon as the audio leaves the phone speaker, the way Spotify
/// surfaces the connected pair. Hidden entirely on the speaker.
class AudioDeviceBadge extends ConsumerWidget {
  final double size;
  final Color color;

  const AudioDeviceBadge({
    super.key,
    this.size = 16,
    this.color = Colors.white70,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(audioOutputDeviceProvider).valueOrNull;
    if (device == null || !device.isExternal) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Icon(
        iconFor(device.device),
        size: size,
        color: color,
      ),
    );
  }
}

IconData iconFor(AudioOutputDevice device) {
  switch (device) {
    case AudioOutputDevice.bluetooth:
      return Icons.headphones_rounded;
    case AudioOutputDevice.wired:
      return Icons.headset_mic_rounded;
    case AudioOutputDevice.usb:
      return Icons.usb_rounded;
    case AudioOutputDevice.speaker:
      return Icons.volume_up_rounded;
  }
}
