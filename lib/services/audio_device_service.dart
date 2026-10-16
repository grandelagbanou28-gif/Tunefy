import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

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

/// Où le son sort réellement, et sous quel nom le système connaît cette
/// sortie. Le nom peut être vide : Android 12+ le refuse sans autorisation
/// Bluetooth, et ce n'est jamais une raison de cacher la route.
class AudioDeviceState {
  final AudioOutputDevice device;
  final String name;
  final bool isExternal;

  const AudioDeviceState(this.device, [this.name = ''])
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
    return _channel.receiveBroadcastStream().map((event) {
      // L'ancien protocole envoyait juste le type en chaîne ; le nouveau envoie
      // une carte {kind, name}. Les deux sont acceptés, un APK partiellement
      // reconstruit ne doit pas vider l'affichage.
      if (event is Map) {
        return AudioDeviceState(
          audioOutputDeviceFrom(event['kind']),
          (event['name'] as String? ?? '').trim(),
        );
      }
      return AudioDeviceState(audioOutputDeviceFrom(event));
    });
  }

  /// Android 12+ ne donne le nom d'un appareil Bluetooth qu'avec
  /// BLUETOOTH_CONNECT. Un seul essai par session : refuser trois fois de suite
  /// serait du harcèlement.
  static Future<void> requestNamePermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_permissionAsked) return;
    _permissionAsked = true;
    try {
      final status = await Permission.bluetoothConnect.status;
      if (status.isGranted || status.isPermanentlyDenied) return;
      await Permission.bluetoothConnect.request();
    } catch (_) {
      // Pas de bloc de service Bluetooth : un nom en moins.
    }
  }

  static bool _permissionAsked = false;
}
