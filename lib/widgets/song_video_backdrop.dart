import 'dart:async';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:muzo/utils/net_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Signal partagé : tant qu'un fond vidéo de paroles est à l'écran, la
/// pochette animée du player doit libérer le décodeur vidéo — Android n'en
/// supporte pas deux sur ce genre d'appareils.
final ValueNotifier<bool> lyricsVideoBackdropOpen = ValueNotifier<bool>(false);

int _backdropSequence = 0;
int? _backdropOwner;

/// Réclame le signal pour l'écran qui va décoder. Retourne le jeton à rendre
/// dans `dispose()` : seul le propriétaire peut éteindre le signal, sinon
/// l'écran qui SORT le remet à false pendant que le nouveau décode encore, et
/// la pochette du player rallume sa propre vidéo → deux décodeurs → crash.
int claimLyricsVideoBackdrop() {
  final id = ++_backdropSequence;
  _backdropOwner = id;
  lyricsVideoBackdropOpen.value = true;
  return id;
}

/// Relâche le signal si et seulement si [id] est bien le détenteur actuel.
void releaseLyricsVideoBackdrop(int? id) {
  if (id == null || _backdropOwner != id) return;
  _backdropOwner = null;
  lyricsVideoBackdropOpen.value = false;
}

/// Fond animé d'un titre : la vidéo du son, muette et en boucle, avec la
/// pochette en repli. Utilisé derrière les paroles pour que l'écran bouge
/// vraiment au lieu de n'être qu'une image floue.
///
/// Une seule vidéo est décodée à la fois : l'appelant doit donc mettre ce
/// widget là où il n'y a pas déjà un lecteur vidéo (la pochette du player
/// suspend sa propre vidéo quand les paroles sont ouvertes).
class SongVideoBackdrop extends ConsumerStatefulWidget {
  final String videoId;
  final String? fallbackImageUrl;

  /// Flou appliqué au rendu : assez fort pour que le texte reste lisible,
  /// nul pour un arrière-plan net.
  final double blurSigma;

  /// Noircissement par-dessus le flou.
  final double dimAlpha;

  const SongVideoBackdrop({
    super.key,
    required this.videoId,
    this.fallbackImageUrl,
    this.blurSigma = 24,
    this.dimAlpha = 0.55,
  });

  @override
  ConsumerState<SongVideoBackdrop> createState() => _SongVideoBackdropState();
}

class _SongVideoBackdropState extends ConsumerState<SongVideoBackdrop>
    with WidgetsBindingObserver {
  static const int _maxBytes = 45 * 1024 * 1024;

  /// Jeton de propriété du signal partagé (voir [claimLyricsVideoBackdrop]).
  int? _backdropToken;

  final YoutubeExplode _yt = YoutubeExplode();
  VideoPlayerController? _controller;
  StreamSubscription<bool>? _playingSub;
  bool _showVideo = false;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant SongVideoBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _playingSub?.cancel();
      _playingSub = null;
      final old = _controller;
      // setState obligatoire : sans rebuild, le VideoPlayer du frame précédent
      // reste accroché à un contrôleur déjà fermé (texture morte → crash natif).
      setState(() {
        _controller = null;
        _showVideo = false;
      });
      old?.dispose();
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playingSub?.cancel();
    releaseLyricsVideoBackdrop(_backdropToken);
    _controller?.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(ui.AppLifecycleState state) {
    if (state == ui.AppLifecycleState.resumed) {
      if (_controller == null) _load();
      return;
    }
    // La surface d'un TextureView est détruite quand l'app quitte le premier
    // plan : un ExoPlayer qui décode encore dessus fait tomber le processus.
    // pause() ne suffit pas, il faut rendre le décodeur.
    final controller = _controller;
    if (controller == null && !_showVideo) return;
    _playingSub?.cancel();
    _playingSub = null;
    _controller = null;
    _loadedFor = null;
    releaseLyricsVideoBackdrop(_backdropToken);
    _backdropToken = null;
    if (mounted) setState(() => _showVideo = false);
    controller?.dispose();
  }

  Future<void> _load() async {
    final videoId = widget.videoId;
    if (videoId.isEmpty || _loadedFor == videoId) return;
    _loadedFor = videoId;
    // Rien n'est décodé pendant la résolution : la pochette du player reprend
    // son décodeur, et le jeton sera reclamé si une vidéo aboutit vraiment.
    releaseLyricsVideoBackdrop(_backdropToken);
    _backdropToken = null;
    _showVideo = false;

    // Sans réseau, la cascade ne peut que perdre du temps : la pochette suffit.
    try {
      final results = await safeConnectivity();
      if (results.contains(ConnectivityResult.none)) return;
    } catch (_) {}

    try {
      final manifest = await _yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 8));
      final muxed = manifest.muxed.toList()
        ..sort((a, b) => a.size.totalBytes.compareTo(b.size.totalBytes));
      String? url;
      if (muxed.isNotEmpty) {
        AudioStreamInfo? best;
        for (final stream in muxed) {
          if (stream.size.totalBytes <= _maxBytes) best = stream;
        }
        url = (best ?? muxed.first).url.toString();
      } else {
        final videoOnly = manifest.videoOnly.toList()
          ..sort((a, b) => a.size.totalBytes.compareTo(b.size.totalBytes));
        if (videoOnly.isNotEmpty) url = videoOnly.first.url.toString();
      }
      if (url == null || !mounted) return;

      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _controller = controller;
      try {
        await controller.initialize().timeout(const Duration(seconds: 10));
      } catch (_) {
        await controller.dispose();
        if (_controller == controller) _controller = null;
        return;
      }
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      // Le son vient du lecteur audio : la vidéo n'apporte que l'image.
      await controller.setVolume(0);
      final handler = ref.read(audioHandlerProvider);
      _playingSub?.cancel();
      _playingSub = handler.player.playingStream.listen((playing) {
        if (!mounted) return;
        if (playing) {
          _controller?.play();
        } else {
          _controller?.pause();
        }
      });
      if (handler.player.playing) await controller.play();
      if (!mounted) return;
      setState(() => _showVideo = true);
      _backdropToken = claimLyricsVideoBackdrop();
    } catch (_) {
      // Pas de vidéo : l'arrière-plan reste la pochette floutée.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final Widget art;
    if (_showVideo && controller != null && controller.value.isInitialized) {
      art = VideoPlayer(controller);
    } else if (widget.fallbackImageUrl != null) {
      art = Image.network(
        widget.fallbackImageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
      );
    } else {
      art = const ColoredBox(color: Colors.black);
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_showVideo && controller != null)
            // La vidéo garde ses proportions et remplit l'écran sans être
            // déformée : un FittedBox cover sur une boîte au bon ratio.
            LayoutBuilder(
              builder: (context, constraints) {
                final ratio = controller.value.aspectRatio == 0
                    ? 16 / 9
                    : controller.value.aspectRatio;
                return Center(
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: ratio,
                        height: 1,
                        child: art,
                      ),
                    ),
                  ),
                );
              },
            )
          else
            art,
          if (widget.blurSigma > 0)
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: widget.blurSigma,
                  sigmaY: widget.blurSigma,
                ),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: widget.dimAlpha),
                ),
              ),
            )
          else
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: widget.dimAlpha),
              ),
            ),
        ],
      ),
    );
  }
}
