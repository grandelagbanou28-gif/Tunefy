import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muzo/providers/audio_device_provider.dart';
import 'package:muzo/services/audio_device_service.dart';
import 'package:muzo/services/storage_service.dart';

/// Spotify-Connect-style device control: an always-visible speaker/cast button
/// on the mini player and the Now Playing screen. Tapping it opens a bottom
/// sheet listing the audio route the system is playing on, the way Spotify
/// surfaces "Play on this device" and the connected pair.
///
/// The phone itself cannot be told to jump audio between arbitrary outputs —
/// Android routes playback to the active accessory automatically — so the sheet
/// reports the real current route (speaker / Bluetooth / wired / USB) instead of
/// faking a Connect switch that would silently do nothing.
class AudioDeviceButton extends ConsumerWidget {
  final double size;
  final Color color;

  /// Affiche en plus le nom réel de la sortie, en vert quand le son quitte le
  /// haut-parleur — ce que demandent le mini-player et Now Playing.
  final bool showName;

  const AudioDeviceButton({
    super.key,
    this.size = 22,
    this.color = Colors.white70,
    this.showName = false,
  });

  static const Color _accent = Color(0xFF1DB954);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioOutputDeviceProvider).valueOrNull ??
        const AudioDeviceState(AudioOutputDevice.speaker);
    final external = state.isExternal;
    final label = external ? _describe(state) : null;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        // Le retour tactile passe avant tout travail asynchrone : la feuille
        // s'ouvre immédiatement, l'autorisation de nom se demande derrière.
        HapticFeedback.selectionClick();
        unawaitedPermissionRequest();
        _openDeviceSheet(context, ref, state);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: showName ? 6 : 0, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_buttonIcon(state.device),
                size: size, color: external ? _accent : color),
            if (showName && label != null) ...[
              const SizedBox(width: 6),
              // Le mini-player est une rangée serrée : le nom ne doit jamais
              // pousser la ligne hors écran.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: external ? _accent : Colors.white70,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Android 12+ only gives the accessory name with BLUETOOTH_CONNECT.
  static void unawaitedPermissionRequest() {
    AudioDeviceService.requestNamePermission();
  }

  /// Speaker glyph while on the phone, otherwise the accessory icon.
  static IconData _buttonIcon(AudioOutputDevice device) {
    if (device == AudioOutputDevice.speaker) return Icons.speaker_rounded;
    return iconFor(device);
  }

  static String _kindLabel(AudioOutputDevice device) => switch (device) {
        AudioOutputDevice.bluetooth => 'Casque Bluetooth',
        AudioOutputDevice.wired => 'Casque filaire',
        AudioOutputDevice.usb => 'Périphérique USB',
        AudioOutputDevice.speaker => 'Ce téléphone',
      };

  /// Le nom rapporté par Android quand il existe, sinon le type d'appareil.
  /// Volontairement court : sur le mini-player, c'est tout l'espace disponible.
  static String _describe(AudioDeviceState state) {
    return state.name.isEmpty ? _kindLabel(state.device) : state.name;
  }

  void _openDeviceSheet(
      BuildContext context, WidgetRef ref, AudioDeviceState state) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        // "Ce téléphone" is always available; the external route only shows
        // when audio is currently leaving the speaker.
        final routes = <AudioOutputDevice>[AudioOutputDevice.speaker];
        if (state.device != AudioOutputDevice.speaker) {
          routes.add(state.device);
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App identity header, like the Spotify "Connect to" screen.
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/icon.png',
                        width: 30,
                        height: 30,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.graphic_eq_rounded,
                          color: _accent,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Tunefy',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '· Lire sur',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (state.device == AudioOutputDevice.speaker)
                  const Text(
                    'Aucun autre appareil connecté. Appairez des écouteurs '
                    'dans les réglages Bluetooth du téléphone : la musique '
                    'basculera automatiquement dessus.',
                    style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.3),
                  ),
                for (final r in routes)
                  _DeviceRow(
                    device: r,
                    active: r == state.device,
                    name: r == state.device ? state.name : '',
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.check_rounded, color: _accent, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'En cours de lecture sur ${_kindLabel(state.device).toLowerCase()}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 10),
                // Deux réglages qui changent réellement le rendu sur la sortie
                // active, plutôt qu'une liste d'options sans effet.
                _SettingTile(
                  storage: ref.read(storageServiceProvider),
                  label: 'Enchaînement croisé',
                  hint: 'Fondu entre deux titres',
                  read: (s) => s.crossfadeEnabled,
                  write: (s, v) => s.setCrossfadeEnabled(v),
                ),
                _SettingTile(
                  storage: ref.read(storageServiceProvider),
                  label: 'Volume régularisé',
                  hint: 'Même forté entre les titres',
                  read: (s) => s.loudnessNormalizationEnabled,
                  write: (s, v) => s.setLoudnessNormalizationEnabled(v),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final AudioOutputDevice device;
  final bool active;
  final String name;
  const _DeviceRow({
    required this.device,
    required this.active,
    this.name = '',
  });

  @override
  Widget build(BuildContext context) {
    final kind = AudioDeviceButton._kindLabel(device);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
        device == AudioOutputDevice.speaker
            ? Icons.phone_iphone_rounded
            : iconFor(device),
        color: active ? AudioDeviceButton._accent : Colors.white70,
      ),
      title: Text(
        name.isEmpty ? kind : name,
        style: TextStyle(
          color: active ? Colors.white : Colors.white70,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: name.isEmpty
          ? null
          : Text(
              kind,
              style: TextStyle(
                fontSize: 12,
                color: active
                    ? AudioDeviceButton._accent
                    : Colors.white38,
              ),
            ),
      trailing: active
          ? const Icon(Icons.check_circle_rounded,
              color: AudioDeviceButton._accent, size: 22)
          : null,
    );
  }
}

/// Un interrupteur branché sur un vrai réglage persisté, qui répond au premier
/// tap.
class _SettingTile extends ConsumerStatefulWidget {
  final StorageService storage;
  final String label;
  final String hint;
  final bool Function(StorageService) read;
  final Future<void> Function(StorageService, bool) write;

  const _SettingTile({
    required this.storage,
    required this.label,
    required this.hint,
    required this.read,
    required this.write,
  });

  @override
  ConsumerState<_SettingTile> createState() => _SettingTileState();
}

class _SettingTileState extends ConsumerState<_SettingTile> {
  late bool _on = widget.read(widget.storage);

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      value: _on,
      activeTrackColor: AudioDeviceButton._accent,
      activeThumbColor: const Color(0xFF121212),
      title: Text(widget.label,
          style: const TextStyle(color: Colors.white, fontSize: 14.5)),
      subtitle:
          Text(widget.hint, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      onChanged: (value) {
        setState(() => _on = value);
        widget.write(widget.storage, value);
      },
    );
  }
}

/// Glyph for each audio route.
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
