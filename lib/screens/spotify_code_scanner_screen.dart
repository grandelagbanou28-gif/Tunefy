import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/screens/global_search_screen.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

enum _ScanMode { camera, gallery, preview, scanning }

class SpotifyCodeScannerScreen extends ConsumerStatefulWidget {
  const SpotifyCodeScannerScreen({super.key});

  @override
  ConsumerState<SpotifyCodeScannerScreen> createState() =>
      _SpotifyCodeScannerScreenState();
}

class _SpotifyCodeScannerScreenState
    extends ConsumerState<SpotifyCodeScannerScreen>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _cameraController;
  bool _isProcessing = false;
  bool _cameraReady = false;
  String? _error;

  _ScanMode _mode = _ScanMode.camera;

  // ─── Gallery state ───
  List<AssetEntity> _galleryAssets = [];
  bool _galleryLoading = false;

  // ─── Preview / scan state ───
  File? _selectedFile;
  bool _scanningQr = false;
  String? _scanError;

  // ─── Shazam state ───
  late stt.SpeechToText _speech;
  bool _shazamListening = false;
  bool _shazamProcessing = false;
  String? _shazamError;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    _startCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _pulseController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _startCamera() async {
    if (_cameraController == null) return;
    try {
      await _cameraController!.start();
      if (mounted) {
        setState(() {
          _cameraReady = true;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() => _error = l10n.cameraUnavailable);
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _isProcessing = true;
        HapticFeedback.selectionClick();
        _cameraController?.stop();
        _saveQrHistory(raw.trim(), 'camera');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GlobalSearchScreen(initialQuery: raw.trim()),
          ),
        );
        break;
      }
    }
  }

  void _saveQrHistory(String value, String source) {
    ref.read(storageServiceProvider).addQrHistory(value: value, source: source);
  }

  // ─── Gallery ───

  Future<void> _toggleGallery() async {
    if (_mode == _ScanMode.gallery) {
      _switchToCamera();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _mode = _ScanMode.gallery;
      _galleryLoading = true;
      _selectedFile = null;
      _scanError = null;
    });
    _cameraController?.stop();
    await _loadGalleryImages();
  }

  Future<void> _loadGalleryImages() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          setState(() {
            _galleryLoading = false;
            _scanError = l10n.permissionDenied;
          });
        }
        return;
      }
      final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      if (albums.isEmpty) {
        if (mounted) {
          setState(() {
            _galleryLoading = false;
            _galleryAssets = [];
          });
        }
        return;
      }
      final assets = await albums.first.getAssetListRange(start: 0, end: 30);
      if (mounted) {
        setState(() {
          _galleryAssets = assets;
          _galleryLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _galleryLoading = false;
          _scanError = l10n.errorLoadingImages;
        });
      }
    }
  }

  Future<void> _selectImage(AssetEntity asset) async {
    HapticFeedback.selectionClick();
    final file = await asset.file;
    if (file == null || !mounted) return;
    setState(() {
      _selectedFile = file;
      _mode = _ScanMode.preview;
      _scanError = null;
    });
  }

  Future<void> _scanSelectedImage() async {
    if (_selectedFile == null) return;
    setState(() {
      _scanningQr = true;
      _scanError = null;
    });
    HapticFeedback.selectionClick();

    final scanner = BarcodeScanner();
    try {
      final inputImage = InputImage.fromFilePath(_selectedFile!.path);
      final barcodes = await scanner.processImage(inputImage);
      String? raw;
      for (final b in barcodes) {
        final v = b.rawValue;
        if (v != null && v.trim().isNotEmpty) {
          raw = v.trim();
          break;
        }
      }
      if (mounted) {
        if (raw != null) {
          _saveQrHistory(raw, 'gallery');
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GlobalSearchScreen(initialQuery: raw),
            ),
          );
        } else {
          final l10n = AppLocalizations.of(context);
          setState(() {
            _scanningQr = false;
            _scanError = l10n.noQRCodeFound;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _scanningQr = false;
          _scanError = l10n.errorAnalyzing;
        });
      }
    } finally {
      await scanner.close();
    }
  }

  void _switchToCamera() {
    setState(() {
      _mode = _ScanMode.camera;
      _selectedFile = null;
      _scanError = null;
    });
    _cameraController?.start();
  }

  // ─── Shazam ───

  Future<void> _startShazam() async {
    if (_shazamListening || _shazamProcessing) {
      _stopShazam();
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _shazamListening = true;
      _shazamProcessing = false;
      _shazamError = null;
    });

    final available = await _speech.initialize(
      onError: (error) {
        if (mounted) {
          setState(() {
            _shazamListening = false;
            _shazamError = 'Microphone error: ${error.errorMsg}';
          });
        }
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (_shazamListening && mounted) {
            _processShazamAudio();
          }
        }
      },
    );

    if (!available) {
      if (mounted) {
        setState(() {
          _shazamListening = false;
          _shazamError = 'Microphone not available';
        });
      }
      return;
    }

    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
        localeId: 'en_US',
      ),
    );

    Timer(const Duration(seconds: 8), () {
      if (_shazamListening) {
        _processShazamAudio();
      }
    });
  }

  Future<void> _processShazamAudio() async {
    if (!_shazamListening) return;
    _speech.stop();

    final recognized = _speech.lastRecognizedWords;
    setState(() {
      _shazamListening = false;
      _shazamProcessing = true;
    });

    if (recognized.trim().isEmpty) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _shazamProcessing = false;
          _shazamError = l10n.noSpeechDetected;
        });
      }
      return;
    }

    setState(() => _shazamProcessing = false);
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GlobalSearchScreen(initialQuery: recognized.trim()),
        ),
      );
    }
  }

  void _stopShazam() {
    _speech.stop();
    if (mounted) {
      setState(() {
        _shazamListening = false;
        _shazamProcessing = false;
      });
    }
  }

  // ─── UI ───

  Widget _compactPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool emphasized = false,
    bool active = false,
    bool expanded = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: expanded ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF1DB954)
              : emphasized
                  ? const Color(0xFF1DB954)
                  : Colors.transparent,
          border: Border.all(
            color: active || emphasized
                ? const Color(0xFF1DB954)
                : Colors.white54,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: active || emphasized ? Colors.black : spotifyWhite,
                size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active || emphasized ? Colors.black : spotifyWhite,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final frameSide =
        (MediaQuery.of(context).size.width - 48).clamp(0.0, 320.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Top bar ───
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 4),
              child: Row(
                children: [
                  const SpotifyBackButton(),
                  const SizedBox(width: 6),
                  Image.asset(
                    'assets/icon.png',
                    width: 28,
                    height: 28,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.album,
                        color: Color(0xFF1DB954),
                        size: 28),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Tunefy',
                    style: TextStyle(
                      color: spotifyWhite,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ─── Main content area ───
            _buildMainContent(frameSide),

            const SizedBox(height: 24),

            // ─── Hint text ───
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _buildHintText(l10n),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // ─── Error ───
            if (_shazamError != null || _scanError != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _shazamError ?? _scanError ?? '',
                  style: const TextStyle(
                      color: Color(0xFF1DB954), fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
            ] else
              const SizedBox(height: 12),

            // ─── Action pills ───
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
              child: Row(
                children: [
                  Expanded(
                    child: _compactPill(
                      icon: _mode == _ScanMode.gallery
                          ? Icons.camera_alt_outlined
                          : Icons.photo_library_outlined,
                      label: _mode == _ScanMode.gallery
                          ? l10n.camera
                          : l10n.gallery,
                      onTap: _mode == _ScanMode.camera
                          ? _toggleGallery
                          : _switchToCamera,
                      active: _mode == _ScanMode.gallery,
                      expanded: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _compactPill(
                      icon: _shazamListening
                          ? Icons.stop_rounded
                          : Icons.bolt_rounded,
                      label: 'Shazam',
                      onTap: _startShazam,
                      active: _shazamListening,
                      emphasized: _shazamProcessing,
                      expanded: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildHintText(AppLocalizations l10n) {
    if (_shazamListening) return l10n.listeningHint;
    if (_shazamProcessing) return l10n.searchingHint;
    if (_mode == _ScanMode.scanning) return l10n.analyzingQrHint;
    if (_mode == _ScanMode.preview) return l10n.pressScanHint;
    if (_mode == _ScanMode.gallery) return l10n.selectImageHint;
    return l10n.pointCameraHint;
  }

  Widget _buildMainContent(double frameSide) {
    switch (_mode) {
      case _ScanMode.camera:
        return Center(child: _shazamListening
            ? _buildShazamPulse(frameSide)
            : _buildCameraFrame(frameSide));

      case _ScanMode.gallery:
        return _buildGalleryGrid();

      case _ScanMode.preview:
      case _ScanMode.scanning:
        return _buildPreview();
    }
  }

  Widget _buildCameraFrame(double frameSide) {
    return Container(
      width: frameSide,
      height: frameSide,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1DB954), width: 2.5),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_cameraReady && _cameraController != null && _error == null)
            MobileScanner(
              controller: _cameraController!,
              onDetect: _onDetect,
            )
          else
            Container(
              color: Colors.black87,
              child: Center(
                child: _error != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off,
                              color: Colors.white54, size: 36),
                          const SizedBox(height: 8),
                          Text(_error!,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 13)),
                        ],
                      )
                    : const SpotifySpinner(
                        color: Color(0xFF1DB954),
                        strokeWidth: 2,
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGalleryGrid() {
    final l10n = AppLocalizations.of(context);
    if (_galleryLoading) {
      return const SizedBox(
        height: 400,
        child: Center(
          child: SpotifySpinner(
              color: Color(0xFF1DB954), strokeWidth: 2),
        ),
      );
    }
    if (_galleryAssets.isEmpty) {
      return SizedBox(
        height: 400,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF1DB954).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_library_outlined,
                    color: Color(0xFF1DB954), size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.noImagesFound,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.galleryAccessPermission,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: 400,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
              child: Row(
                children: [
                  const Icon(Icons.photo_library_outlined, color: Color(0xFF1DB954), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    l10n.myPhotos,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    l10n.imagesCount(_galleryAssets.length),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: _galleryAssets.length,
                itemBuilder: (ctx, i) {
                  final asset = _galleryAssets[i];
                  return GestureDetector(
                    onTap: () => _selectImage(asset),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: FutureBuilder<Uint8List?>(
                        future: asset.thumbnailDataWithSize(
                          const ThumbnailSize(200, 200),
                        ),
                        builder: (ctx, snap) {
                          if (snap.hasData && snap.data != null) {
                            return Image.memory(
                              snap.data!,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            );
                          }
                          return Container(
                            color: spotifyDarkGrey,
                            child: const Center(
                              child: Icon(Icons.image_outlined,
                                  color: Colors.white24, size: 24),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final l10n = AppLocalizations.of(context);
    if (_selectedFile == null) {
      return const SizedBox(
        height: 320,
        child: Center(
          child: SpotifySpinner(
              color: Color(0xFF1DB954), strokeWidth: 2),
        ),
      );
    }
    return SizedBox(
      height: 320,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.file(
                    _selectedFile!,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => Container(
                      color: spotifyDarkGrey,
                      child: const Center(
                        child: Icon(Icons.image_outlined,
                            color: Colors.white24, size: 64),
                      ),
                    ),
                  ),
                  if (_scanningQr)
                    Container(
                      color: Colors.black.withValues(alpha: 0.6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SpotifySpinner(
                            color: Color(0xFF1DB954),
                            strokeWidth: 2.5,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.analyzingQrHint,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _scanningQr
                      ? null
                      : () {
                          setState(() {
                            _mode = _ScanMode.gallery;
                            _selectedFile = null;
                            _scanError = null;
                          });
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: Colors.white54),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_library_outlined,
                            color: spotifyWhite, size: 18),
                        const SizedBox(width: 8),
                        Text(l10n.anotherImage,
                            style: TextStyle(
                                color: spotifyWhite,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _scanningQr ? null : _scanSelectedImage,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1DB954),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _scanningQr
                              ? Icons.hourglass_top_rounded
                              : Icons.qr_code_scanner_rounded,
                          color: Colors.black,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _scanningQr ? 'Analyse...' : l10n.scan,
                          style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                              fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
      ),
    );
  }

  Widget _buildShazamPulse(double size) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final t = _pulseController.value;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1DB954)
                .withValues(alpha: 0.08 + 0.15 * t),
            border: Border.all(
              color: const Color(0xFF1DB954)
                  .withValues(alpha: 0.3 + 0.5 * t),
              width: 2 + 2 * t,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/covers/app_icon.png',
                  width: 64 + 16 * t,
                  height: 64 + 16 * t,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.album,
                    color: const Color(0xFF1DB954)
                        .withValues(alpha: 0.6 + 0.4 * t),
                    size: 64 + 16 * t,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tunefy',
                  style: TextStyle(
                    color: const Color(0xFF1DB954)
                        .withValues(alpha: 0.5 + 0.5 * t),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ecoute...',
                  style: TextStyle(
                    color:
                        Colors.white.withValues(alpha: 0.4 + 0.3 * t),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
