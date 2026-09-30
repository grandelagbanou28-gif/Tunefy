import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AudioOutputDevice { speaker, bluetooth, wired, usb }

AudioOutputDevice audioOutputDeviceFrom(Object? raw) {
  switch (raw) {
    case 'bluetooth':
      return AudioOutputDevice.bluetooth;
    case 'wired':
      return AudioOutputDevice.wired;
    case 'usb':
      return AudioOutputDevice.usb;
    default:
      return AudioOutputDevice.speaker;
  }
}

/// Where the audio is currently routed. The kind of device is all we expose,
/// so no runtime permission is needed on Android.
class AudioDeviceState {
  final AudioOutputDevice device;
  final bool isExternal;

  const AudioDeviceState(this.device)
    : isExternal = device != AudioOutputDevice.speaker;
}

/// Mirrors the output device the system is playing on, the way the big music
/// apps show a headphone glyph in the mini player once a pair is connected.
class AudioDeviceService {
  static const EventChannel _channel = EventChannel(
    'com.shashwat.muzo/audio_device',
  );

  static Stream<AudioDeviceState> watch() {
    if (kIsWeb || !Platform.isAndroid) {
      return Stream<AudioDeviceState>.value(
        const AudioDeviceState(AudioOutputDevice.speaker),
      );
    }
    return _channel.receiveBroadcastStream().map(
      (event) => AudioDeviceState(audioOutputDeviceFrom(event)),
    );
  }
}
