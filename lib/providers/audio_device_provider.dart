import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/services/audio_device_service.dart';

/// Output device the system is currently routing audio to. Starts on the
/// phone speaker and flips to headphones as soon as a pair is connected.
final audioOutputDeviceProvider = StreamProvider<AudioDeviceState>((ref) {
  return AudioDeviceService.watch();
});
