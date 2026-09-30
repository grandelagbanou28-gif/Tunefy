import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:muzo/services/storage_service.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/settings_provider.dart';
import 'package:muzo/providers/theme_provider.dart';
import 'package:muzo/screens/artist_database_debug_screen.dart';
import 'package:muzo/screens/moov_thanks_screen.dart';
import 'package:muzo/services/stream_endpoint_resolver.dart';
import 'package:muzo/services/stream_extraction_service.dart';
import 'package:muzo/services/stream_prewarmer.dart';
import 'package:muzo/services/lyrics_translation_service.dart';
import 'package:muzo/services/youtube_music_auth.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/utils/app_colors.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/widgets/spotify_spinner.dart';
import 'package:hive/hive.dart';

const Color _hivefyBgColor = Color(0xFF121212);
const Color _hivefyGreen = Color(0xFF1DDA63);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool notificationsEnabled = false;
  bool _isTitleCollapsed = false;
  late ScrollController _scrollController;
  final DiskSpacePlus diskSpacePlus = DiskSpacePlus();
  late Future<List<dynamic>> _storageFuture;
  static const Map<String, String> _streamServers = {
    'Auto': '',
    'Main Server': StreamExtractionService.cloudYtDlpBase,
    'Backup Server': StreamExtractionService.cloudBackupYtDlpBase,
    'Local Server': 'http://127.0.0.1:9877',
    'Freedify': StreamExtractionService.freedifyBase,
  };

  String _selectedServer = 'Auto';
  String? _activeBase;
  final TextEditingController _ytdlpController = TextEditingController();
  final TextEditingController _deeplController = TextEditingController();
  bool _shuffleEnabled = false;
  bool _smartShuffleEnabled = true;
  bool _crossfadeEnabled = false;
  int _crossfadeSeconds = 6;
  bool _gaplessEnabled = true;
  bool _loudnessNormalization = false;
  bool _dynamicColorEnabled = true;

  @override
  void initState() {
    super.initState();

    _loadYtDlpServerUrl();
    _loadDeeplApiKey();
    _loadPlaybackSettings();

    _scrollController =
        ScrollController()..addListener(() {
          final offset = _scrollController.offset;
          if (offset > 120 && !_isTitleCollapsed) {
            setState(() => _isTitleCollapsed = true);
          } else if (offset <= 120 && _isTitleCollapsed) {
            setState(() => _isTitleCollapsed = false);
          }
        });
    _checkNotificationStatus();
    _refreshStorageFuture();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _ytdlpController.dispose();
    _deeplController.dispose();
    super.dispose();
  }

  Future<void> _loadDeeplApiKey() async {
    final service = LyricsTranslationService();
    final key = await service.getStoredDeeplApiKey();
    _deeplController.text = key ?? '';
    if (mounted) setState(() {});
  }

  void _loadPlaybackSettings() {
    final storage = ref.read(storageServiceProvider);
    _shuffleEnabled = storage.shuffleEnabled;
    _smartShuffleEnabled = storage.smartShuffleEnabled;
    _crossfadeEnabled = storage.crossfadeEnabled;
    _crossfadeSeconds = storage.crossfadeSeconds;
    _gaplessEnabled = storage.gaplessEnabled;
    _loudnessNormalization = storage.loudnessNormalizationEnabled;
    _dynamicColorEnabled = storage.dynamicColorEnabled;
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _SettingsSwitchTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildSliderTile({
    required IconData icon,
    required String title,
    required double value,
    required double min,
    required double max,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    return _SettingsSliderTile(
      icon: icon,
      title: title,
      value: value,
      min: min,
      max: max,
      valueLabel: valueLabel,
      onChanged: onChanged,
    );
  }

  Widget _buildQualitySelector() {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(settingsProvider).audioQuality;
    final options = <AudioQuality, String>{
      AudioQuality.high: l10n.highAudioQuality,
      AudioQuality.medium: l10n.mediumAudioQuality,
      AudioQuality.low: l10n.lowAudioQuality,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _hivefyGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.high_quality, size: 22, color: _hivefyGreen),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.audioQuality,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.audioQualityDesc,
                      style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.entries.map((entry) {
              final isSelected = entry.key == selected;
              return ChoiceChip(
                label: Text(
                  entry.value,
                  style: TextStyle(
                    color: isSelected ? _hivefyGreen : Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                selected: isSelected,
                selectedColor: _hivefyGreen.withValues(alpha: 0.2),
                backgroundColor: AppColors.cardTranslucent,
                showCheckmark: false,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? _hivefyGreen : Colors.grey.shade800,
                    width: isSelected ? 1 : 0,
                  ),
                ),
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  ref.read(settingsProvider.notifier).setAudioQuality(entry.key);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDeeplApiKey() async {
    final key = _deeplController.text.trim();
    final service = LyricsTranslationService();
    final l10n = AppLocalizations.of(context);
    if (key.isEmpty) {
      await service.clearDeeplApiKey();
      _showSnack(l10n.deeplKeyCleared);
      return;
    }
    await service.setDeeplApiKey(key);
    _showSnack(l10n.deeplKeySaved);
  }

  Future<void> _loadYtDlpServerUrl() async {
    try {
      final box = Hive.isBoxOpen('settings')
          ? Hive.box('settings')
          : await Hive.openBox('settings');
      final saved = (box.get('ytdlpServerUrl') as String?)?.trim();
      // No pin means Auto: the resolver decides at runtime.
      final label =
          (saved == null || saved.isEmpty) ? 'Auto' : _serverLabelForUrl(saved);
      _ytdlpController.text = saved ?? '';
      _selectedServer = label.isEmpty ? 'Auto' : label;
      _activeBase = (box.get('stream_active_base') as String?)?.trim();
      if (mounted) setState(() {});
    } catch (_) {
      _ytdlpController.text = '';
      _selectedServer = 'Auto';
    }
  }

  String _serverLabelForUrl(String url) {
    for (final entry in _streamServers.entries) {
      if (url.trim() == entry.value) return entry.key;
    }
    return '';
  }

  static String _shortHost(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    return host.replaceFirst('www.', '');
  }

  /// Probes every candidate and reports which one answers, so a broken
  /// Liveness of the loopback resolver. It is the only source that resolves on
  /// the device's own IP, so when it is down nothing plays — and the symptom is
  /// indistinguishable from "this song is broken".
  Future<bool> _probeLocalServer() async {
    try {
      final client = http.Client();
      try {
        final resp = await client
            .get(Uri.parse('http://127.0.0.1:9877/health'))
            .timeout(const Duration(seconds: 4));
        return resp.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Observability for playback. A silent failure is the worst kind: the listener
  /// only sees a song that will not play, with no way to tell a dead resolver
  /// from an unplayable track. This card names every source, its current state,
  /// and lets the parked ones be put back into rotation.
  Widget _buildSourceHealthCard(BuildContext context) {
    final report = StreamExtractionService.sourceHealthReport();
    final entries = report.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final parked = entries.where((e) => e.value.startsWith('hors service')).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardTranslucent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade800, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq,
                  size: 18, color: parked > 0 ? Colors.orangeAccent : _hivefyGreen),
              const SizedBox(width: 8),
              Text(
                'Sources audio',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            StreamPrewarmer.instance.report(),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          FutureBuilder<bool>(
            future: _probeLocalServer(),
            builder: (context, snap) {
              final up = snap.data;
              final label = up == null
                  ? 'Vérification du serveur local…'
                  : up
                      ? 'Serveur local : actif (127.0.0.1:9877)'
                      : 'Serveur local : arrêté — rien ne peut se lire';
              final color = up == null
                  ? Colors.white38
                  : up
                      ? _hivefyGreen
                      : Colors.redAccent;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        up == null
                            ? Icons.hourglass_empty
                            : up
                                ? Icons.check_circle
                                : Icons.cancel,
                        size: 14,
                        color: color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                              color: color, fontSize: 12.5, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                  if (up == false) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Lance : python backend\\local_stream_server.py --port 9877'
                      '\npuis : adb reverse tcp:9877 tcp:9877',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 11.5, height: 1.4),
                    ),
                  ],
                ],
              );
            },
          ),
          if (entries.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Aucune source testée pour l\'instant. Lance une lecture pour la mesurer.',
              style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.3),
            ),
          ] else ...[
            const SizedBox(height: 10),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      e.value == 'ok'
                          ? Icons.check_circle
                          : e.value.startsWith('hors service')
                              ? Icons.cancel
                              : Icons.remove_circle_outline,
                      size: 14,
                      color: e.value == 'ok'
                          ? _hivefyGreen
                          : e.value.startsWith('hors service')
                              ? Colors.redAccent
                              : Colors.white38,
                    ),
                    const SizedBox(width: 8),
                    Text(e.key,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12.5)),
                    const Spacer(),
                    Text(e.value,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                StreamExtractionService.resetSourceHealth();
                setState(() {});
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Réessayer toutes les sources'),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  /// Server is visible here instead of surfacing as "playback failed".
  Widget _buildTestServerButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StatefulBuilder(
      builder: (context, setInner) {
        return TextButton.icon(
          onPressed: () async {
            HapticFeedback.selectionClick();
            setInner(() {});
            final healthy = await StreamEndpointResolver().healthyBases(force: true);
            if (!mounted) return;
            setState(() {
              _activeBase = healthy.isEmpty ? null : healthy.first;
            });
            setInner(() {});
            _showSnack(
              healthy.isEmpty
                  ? l10n.streamServerTestFail
                  : '${l10n.streamServerTestOk} · ${_shortHost(healthy.first)}',
              error: healthy.isEmpty,
            );
          },
          icon: const Icon(Icons.wifi_tethering, size: 18),
          label: Text(l10n.streamServerTest),
          style: TextButton.styleFrom(
            foregroundColor: _hivefyGreen,
            visualDensity: VisualDensity.compact,
          ),
        );
      },
    );
  }

  Future<void> _selectServer(String server) async {
    final base = _streamServers[server];
    if (base == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _selectedServer = server);
    _ytdlpController.text = base;
    try {
      final box = Hive.isBoxOpen('settings')
          ? Hive.box('settings')
          : await Hive.openBox('settings');
      await box.put('streamServer', server);
      // "Auto" clears the pin so the resolver picks whichever host answers.
      if (base.isEmpty) {
        await box.delete('ytdlpServerUrl');
        // Re-test every candidate, including hosts the breaker had open.
        await StreamEndpointResolver.resetCircuitBreaker();
      } else {
        await box.put('ytdlpServerUrl', base);
      }
      _showSnack(l10n.serverUpdated);
    } catch (e) {
      _showSnack(l10n.failedToSave(e.toString()), error: true);
    }
  }

  Future<void> _saveYtDlpServerUrl() async {
    final url = _ytdlpController.text.trim();
    final l10n = AppLocalizations.of(context);
    if (url.isEmpty) {
      _showSnack(l10n.urlCannotBeEmpty, error: true);
      return;
    }
    try {
      final box = Hive.isBoxOpen('settings')
          ? Hive.box('settings')
          : await Hive.openBox('settings');
      await box.put('ytdlpServerUrl', url);
      _showSnack(l10n.serverUpdated);
    } catch (e) {
      _showSnack(l10n.failedToSave(e.toString()), error: true);
    }
  }

  Future<void> _testYtDlpServer() async {
    final url = _ytdlpController.text.trim();
    final l10n = AppLocalizations.of(context);
    // Freedify exposes /api/health (FastAPI), local/Vercel use /health.
    final healthPath = url.contains('8000') || url.contains('freedify')
        ? '/api/health'
        : '/health';
    final healthUrl = Uri.parse('$url$healthPath');
    try {
      final res = await http
          .get(healthUrl)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        _showSnack(l10n.serverReachable);
      } else {
        _showSnack(l10n.serverReplied(res.statusCode), error: true);
      }
    } catch (_) {
      _showSnack(l10n.serverUnreachable, error: true);
    }
  }

  Future<void> _checkNotificationStatus() async {
    final status = await Permission.notification.status;
    if (mounted) setState(() => notificationsEnabled = status.isGranted);
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    if (mounted) setState(() => notificationsEnabled = status.isGranted);
    if (!status.isGranted) openAppSettings();
  }

  Future<double> getDeviceStorageInBytes() async {
    try {
      // Total disk space in MB
      final totalMB = await diskSpacePlus.getTotalDiskSpace ?? 0;

      // Optional: free space in app directory
      final dir = await getApplicationDocumentsDirectory();
      final freeMB = await diskSpacePlus.getFreeDiskSpaceForPath(dir.path) ?? 0;

      debugPrint('--> free space $freeMB MB, total $totalMB MB');

      // Use totalMB if valid, otherwise fallback to 32 GB (converted to MB)
      final safeMB =
          (totalMB > 0 && totalMB < 1024 * 1024) ? totalMB : 32 * 1024;

      return safeMB * 1024 * 1024; // convert MB → bytes
    } catch (_) {
      return 32 * 1024 * 1024 * 1024; // fallback 32 GB in bytes
    }
  }

  // Refresh the storage future whenever needed
  void _refreshStorageFuture() {
    final storage = ref.read(storageServiceProvider);
    _storageFuture = Future.wait([
      storage.downloadsTotalBytes().then((b) => b.toDouble()), // offline bytes
      storage.downloadsTotalBytes().then((b) => _formatBytes(b.toDouble())),
      getDeviceStorageInBytes(), // returns totalBytes in bytes
    ]);
    if (mounted) setState(() {});
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    showGlassSnackBar(context, message, error: error);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: _hivefyBgColor,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // --- Collapsible AppBar ---
          SliverAppBar(
            pinned: true,
            expandedHeight: 160,
            backgroundColor: _darkerGreen(_hivefyGreen),
            leading: const BackButton(color: Colors.white),
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                final minHeight = kToolbarHeight;
                final maxHeight = 160.0;
                final collapsePercent = ((constraints.maxHeight - minHeight) /
                        (maxHeight - minHeight))
                    .clamp(0.0, 1.0);

                return FlexibleSpaceBar(
                  centerTitle: false,
                  titlePadding: EdgeInsets.only(
                    left: _isTitleCollapsed ? 72 : 16,
                    bottom: 16,
                    right: 16,
                  ),
                  title: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isTitleCollapsed ? 1.0 : 0.0,
                    child: Text(
                      l10n.settings,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  background: Container(
                    color: _hivefyBgColor,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 32),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Opacity(
                          opacity: collapsePercent,
                          child: Text(
                            l10n.settings,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // --- Notifications ---
          _buildSectionTitle(
            l10n.notifications,
            subtitle: l10n.manageNotifications,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _hivefyGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        notificationsEnabled
                            ? Icons.notifications
                            : Icons.notifications_off,
                        size: 22,
                        color: _hivefyGreen,
                      ),
                    ),
                    const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.appNotifications,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notificationsEnabled
                              ? l10n.notificationsUpdateText
                              : l10n.notificationsOffText,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!notificationsEnabled)
                    TextButton(
                      onPressed: _requestNotificationPermission,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        side: const BorderSide(
                          color: Colors.greenAccent,
                          width: 1,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text(
                        l10n.enable,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _buildDivider(),

          // --- User Preferences ---
          _buildSectionTitle(
            l10n.preferences,
            subtitle: l10n.managePreferences,
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              SettingsRow(
                icon: Icons.music_note,
                title: l10n.lastPlayedSongs,
                content: l10n.clearLastPlayed,
                onDelete: () async {
                  final storage = ref.read(storageServiceProvider);
                  await storage.clearHistory();
                  _showSnack(l10n.lastPlayedCleared);
                },
              ),
              SettingsRow(
                icon: Icons.search,
                title: l10n.searchHistory,
                content: l10n.clearSearchHistory,
                onDelete: () async {
                  final storage = ref.read(storageServiceProvider);
                  await storage.clearSearchHistory();
                  _showSnack(l10n.searchHistoryCleared);
                },
              ),
            ]),
          ),
          _buildDivider(),

          // --- Offline Manager Section ---
          _buildSectionTitle(
            l10n.offlineManager,
            subtitle: l10n.manageOffline,
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              SettingsRow(
                icon: Icons.download_done,
                title: l10n.deleteAllOfflineSongs,
                content: l10n.deleteAllOfflineConfirm,
                onDelete: () async {
                  final storage = ref.read(storageServiceProvider);
                  await storage.clearDownloads();
                  _showSnack(l10n.allOfflineDeleted);
                  _refreshStorageFuture(); // refresh storage info after deletion
                },
              ),
            ]),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FutureBuilder<List<dynamic>>(
                future: _storageFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: SizedBox(
                        height: 40,
                        width: 40,
                        child: SpotifySpinner(strokeWidth: 2),
                      ),
                    );
                  }

                  final offlineBytes = snapshot.data![0] as double; // our app
                  final usedFormatted = snapshot.data![1] as String;
                  final totalBytes = snapshot.data![2] as double; // total
                  final freeBytes = totalBytes - offlineBytes; // rough free

                  // fractions for bar
                  final appFraction =
                      (offlineBytes / totalBytes).clamp(0.0, 1.0) + 0.01;
                  final otherFraction =
                      ((freeBytes - (totalBytes - freeBytes)) / totalBytes)
                          .clamp(0.0, 1.0);
                  final freeFraction = (freeBytes / totalBytes).clamp(0.0, 1.0);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.offlineSongsUsed(usedFormatted),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            flex: (appFraction * 1000).toInt(),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(5),
                                bottomLeft: Radius.circular(5),
                              ),
                              child: Container(
                                height: 6,
                                color: _hivefyGreen,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: (otherFraction * 1000).toInt(),
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: (freeFraction * 1000).toInt(),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(5),
                                bottomRight: Radius.circular(5),
                              ),
                              child: Container(
                                height: 6,
                                color: Colors.white12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            l10n.usedFormatted({
                              'size': _formatBytes(offlineBytes),
                            }),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            "${_formatBytes(totalBytes)} ${l10n.total}",
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          _buildDivider(),

          // --- API Server Selection ---
          _buildSectionTitle(
            l10n.streamServer,
            subtitle: _activeBase == null
                ? l10n.chooseStreamServer
                : '${l10n.streamServerActive}: ${_shortHost(_activeBase!)}',
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _streamServers.keys.map((server) {
                      final isSelected = server == _selectedServer;

                      return ChoiceChip(
                        label: Text(
                          isSelected
                              ? server
                              : server.replaceAll(" Server", ""),
                          style: TextStyle(
                            color: isSelected ? _hivefyGreen : Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        selected: isSelected,
                        color: WidgetStateProperty.resolveWith<Color?>((states) {
                          return AppColors.cardTranslucent;
                        }),
                        selectedColor: _hivefyGreen.withAlpha(51),
                        backgroundColor: AppColors.cardTranslucent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected
                                ? _hivefyGreen
                                : Colors.grey.shade800,
                            width: isSelected ? 1 : 0,
                          ),
                        ),
                        showCheckmark: false,
                        onSelected: (_) => _selectServer(server),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.settingsServerSwitchHint,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildTestServerButton(context),
                    ],
                  ),

                  const SizedBox(height: 16),
                  _buildSourceHealthCard(context),

                  const SizedBox(height: 20),
                  Text(
                    l10n.localYTDLP,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.ytDlpInfo,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ytdlpController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white10,
                      hintText: 'https://…',
                      hintStyle: const TextStyle(color: Colors.white30),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _saveYtDlpServerUrl,
                        style: FilledButton.styleFrom(
                          backgroundColor: _hivefyGreen,
                          foregroundColor: Colors.black,
                        ),
                        child: Text(l10n.save),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _testYtDlpServer,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _hivefyGreen,
                          side: const BorderSide(color: _hivefyGreen),
                        ),
                        child: Text(l10n.test),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _buildDivider(),

          // --- YouTube Music Auth ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _YouTubeMusicAuthSection(),
            ),
          ),
          _buildDivider(),

          // --- Moov Celestis (remerciement post-paiement) ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildMoovThanksEntry(l10n),
            ),
          ),
          _buildDivider(),

          // --- Playback Section ---
          _buildSectionTitle(
            l10n.playback,
            subtitle: l10n.playbackDesc,
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              _buildSwitchTile(
                icon: Icons.shuffle,
                title: l10n.shuffle,
                subtitle: l10n.shuffleDesc,
                value: _shuffleEnabled,
                onChanged: (value) async {
                  setState(() => _shuffleEnabled = value);
                  await ref.read(audioHandlerProvider).setShuffleEnabled(value);
                },
              ),
              _buildSwitchTile(
                icon: Icons.auto_awesome,
                title: l10n.smartShuffle,
                subtitle: l10n.smartShuffleDesc,
                value: _smartShuffleEnabled,
                onChanged: (value) async {
                  setState(() => _smartShuffleEnabled = value);
                  await ref
                      .read(audioHandlerProvider)
                      .setSmartShuffleEnabled(value);
                },
              ),
              _buildSwitchTile(
                icon: Icons.merge,
                title: l10n.crossfade,
                subtitle: l10n.crossfadeDesc,
                value: _crossfadeEnabled,
                onChanged: (value) async {
                  setState(() => _crossfadeEnabled = value);
                  await ref.read(audioHandlerProvider).setCrossfadeEnabled(value);
                  if (value) {
                    setState(() => _gaplessEnabled = false);
                  }
                },
              ),
              if (_crossfadeEnabled)
                _buildSliderTile(
                  icon: Icons.timelapse,
                  title: l10n.crossfadeDuration,
                  value: _crossfadeSeconds.toDouble(),
                  min: 1,
                  max: 12,
                  valueLabel: '${_crossfadeSeconds}s',
                  onChanged: (value) async {
                    setState(() => _crossfadeSeconds = value.round());
                    await ref
                        .read(audioHandlerProvider)
                        .setCrossfadeSeconds(value.round());
                  },
                ),
              _buildSwitchTile(
                icon: Icons.all_inclusive,
                title: l10n.gapless,
                subtitle: l10n.gaplessDesc,
                value: _gaplessEnabled,
                onChanged: (value) async {
                  setState(() => _gaplessEnabled = value);
                  await ref.read(audioHandlerProvider).setGaplessEnabled(value);
                  if (value) {
                    setState(() => _crossfadeEnabled = false);
                  }
                },
              ),
              _buildSwitchTile(
                icon: Icons.equalizer,
                title: l10n.loudnessNormalization,
                subtitle: l10n.loudnessNormalizationDesc,
                value: _loudnessNormalization,
                onChanged: (value) async {
                  setState(() => _loudnessNormalization = value);
                  await ref
                      .read(audioHandlerProvider)
                      .setLoudnessNormalization(value);
                },
              ),
              _buildSwitchTile(
                icon: Icons.palette_outlined,
                title: l10n.dynamicColor,
                subtitle: l10n.dynamicColorDesc,
                value: _dynamicColorEnabled,
                onChanged: (value) async {
                  setState(() => _dynamicColorEnabled = value);
                  await ref
                      .read(storageServiceProvider)
                      .setDynamicColorEnabled(value);
                  final notifier = ref.read(albumArtColorProvider.notifier);
                  notifier.state = value ? ref.read(themeColorProvider) : null;
                },
              ),
              _buildQualitySelector(),
            ]),
          ),
          _buildDivider(),

          // --- Lyrics Translation (DeepL) ---
          _buildSectionTitle(
            l10n.lyricsTranslation,
            subtitle: l10n.lyricsTranslationDesc,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.deeplApiKeyLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.deeplApiKeyHint,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _deeplController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    obscureText: true,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white10,
                      hintText: l10n.deeplApiKeyLabel,
                      hintStyle: const TextStyle(color: Colors.white30),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _saveDeeplApiKey,
                      style: FilledButton.styleFrom(
                        backgroundColor: _hivefyGreen,
                        foregroundColor: Colors.black,
                      ),
                      child: Text(l10n.saveKey),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildDivider(),

          // --- Debug Section ---
          _buildSectionTitle(
            l10n.debug,
            subtitle: l10n.debugDesc,
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              _buildDebugTile(
                icon: Icons.storage,
                title: l10n.artistDatabase,
                subtitle: l10n.artistDbDesc,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ArtistDatabaseDebugScreen(),
                    ),
                  );
                },
              ),
            ]),
          ),
          _buildDivider(),

          // --- Main Database Caches ---
          _buildSectionTitle(
            l10n.caches,
            subtitle: l10n.cachesDesc,
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              SettingsRow(
                icon: Icons.music_note,
                title: l10n.songsCache,
                content: l10n.songsCacheDesc,
                onDelete: () async {
                  final storage = ref.read(storageServiceProvider);
                  await storage.clearSongsCache();
                  _showSnack(l10n.songsCleared);
                },
              ),
              SettingsRow(
                icon: Icons.person,
                title: l10n.artistCache,
                content: l10n.artistCacheDesc,
                onDelete: () async {
                  final storage = ref.read(storageServiceProvider);
                  await storage.clearArtistCache();
                  _showSnack(l10n.artistCleared);
                },
              ),
              SettingsRow(
                icon: Icons.album,
                title: l10n.albumCache,
                content: l10n.albumCacheDesc,
                onDelete: () async {
                  final storage = ref.read(storageServiceProvider);
                  await storage.clearAlbumCache();
                  _showSnack(l10n.albumCleared);
                },
              ),
              SettingsRow(
                icon: Icons.queue_music,
                title: l10n.playlistCache,
                content: l10n.playlistCacheDesc,
                onDelete: () async {
                  final storage = ref.read(storageServiceProvider);
                  await storage.clearPlaylistCache();
                  _showSnack(l10n.playlistsCleared);
                },
              ),
            ]),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildSectionTitle(String title, {String? subtitle}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildDivider() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Divider(color: Colors.white12, thickness: 1),
      ),
    );
  }

  /// Moov Celestis — accès à l'aperçu du remerciement qui sera affiché après
  /// un paiement confirmé (quand la passerelle PSP sera branchée).
  Widget _buildMoovThanksEntry(AppLocalizations l10n) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white10,
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1DB954), Color(0xFF1DDA63)],
              ),
            ),
            child: const Icon(Icons.mobile_friendly,
                color: Colors.black, size: 22),
          ),
          title: Text(
            l10n.moovCelestis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            l10n.moovThanksPreview,
            style:
                const TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          trailing: const Icon(Icons.chevron_right,
              color: Colors.white38, size: 22),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MoovThanksScreen(credits: 1),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDebugTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Colors.white.withValues(alpha: 0.3),
      ),
      onTap: onTap,
    );
  }
}

Color _darkerGreen(Color color, {double darkenFactor = 0.18}) {
  final hsl = HSLColor.fromColor(color);
  final newLight = (hsl.lightness - darkenFactor).clamp(0.12, 1.0);
  final newSat = (hsl.saturation + 0.1).clamp(0.0, 1.0);
  return hsl.withLightness(newLight).withSaturation(newSat).toColor();
}

// --- SettingsRow with improved spacing ---
class SettingsRow extends StatelessWidget {
  final String title;
  final String content;
  final IconData icon;
  final VoidCallback onDelete;
  final bool showDelete;

  const SettingsRow({
    super.key,
    required this.title,
    required this.content,
    required this.icon,
    required this.onDelete,
    this.showDelete = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _hivefyGreen.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: _hivefyGreen),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          if (showDelete)
            TextButton(
              onPressed: onDelete,
              style: TextButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: Colors.white30, width: 1),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                AppLocalizations.of(context).clear,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _YouTubeMusicAuthSection extends ConsumerStatefulWidget {
  const _YouTubeMusicAuthSection();

  @override
  ConsumerState<_YouTubeMusicAuthSection> createState() => _YouTubeMusicAuthSectionState();
}

class _YouTubeMusicAuthSectionState extends ConsumerState<_YouTubeMusicAuthSection> {
  bool _isAuthenticating = false;
  String? _userCode;
  String? _verificationUrl;
  String? _deviceCode;
  int _pollInterval = 5;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = YouTubeMusicAuth.instance;
    final isAuth = auth.isAuthenticated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isAuth ? Icons.music_note : Icons.music_off,
              color: isAuth ? _hivefyGreen : Colors.white60,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              isAuth ? l10n.ytMusicConnected : l10n.ytMusicNotConnected,
              style: TextStyle(
                color: isAuth ? _hivefyGreen : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
        if (isAuth) ...[
          const SizedBox(height: 4),
          Text(
            auth.email ?? '',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await auth.clearAuth();
                setState(() {});
              },
              icon: const Icon(Icons.logout, size: 16, color: Colors.redAccent),
              label: Text(l10n.signOut,
                  style: const TextStyle(color: Colors.redAccent)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            l10n.ytMusicSignInHint,
            style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 12),
          if (_userCode != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    l10n.ytMusicGoTo,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _verificationUrl ?? 'https://www.google.com/device',
                    style: const TextStyle(
                      color: _hivefyGreen,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.ytMusicEnterCode,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userCode!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_isAuthenticating)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: SpotifySpinner(strokeWidth: 2, color: _hivefyGreen),
                    ),
                ],
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isAuthenticating ? null : _startDeviceFlow,
                icon: _isAuthenticating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: SpotifySpinner(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.login, size: 16),
                label: Text(_isAuthenticating
                    ? l10n.ytMusicWaiting
                    : l10n.ytMusicConnect),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hivefyGreen,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _startDeviceFlow() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isAuthenticating = true;
      _userCode = null;
    });

    try {
      final result = await YouTubeMusicAuth.instance.startDeviceFlow();
      if (result == null) {
        setState(() => _isAuthenticating = false);
        if (mounted) {
          showGlassSnackBar(context, l10n.ytMusicOAuthError, error: true);
        }
        return;
      }

      setState(() {
        _deviceCode = result['device_code'];
        _userCode = result['user_code'];
        _verificationUrl = result['verification_url'];
        _pollInterval = int.tryParse(result['interval'] ?? '5') ?? 5;
      });

      // Start polling in background
      _pollForAuth();
    } catch (e) {
      setState(() => _isAuthenticating = false);
      if (mounted) {
        showGlassSnackBar(context,
            l10n.ytMusicError({'error': e.toString()}), error: true);
      }
    }
  }

  Future<void> _pollForAuth() async {
    final l10n = AppLocalizations.of(context);
    final deviceCode = _deviceCode;
    if (deviceCode == null) return;

    final success = await YouTubeMusicAuth.instance.pollDeviceFlow(
      deviceCode,
      interval: _pollInterval,
    );

    if (success && mounted) {
      setState(() {
        _isAuthenticating = false;
        _userCode = null;
      });
      showGlassSnackBar(context, l10n.ytMusicConnectedSuccess);
    } else if (mounted) {
      setState(() => _isAuthenticating = false);
    }
  }
}

String _formatBytes(double bytes) {
  if (bytes <= 0) return "0 B";

  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;

  if (bytes >= gb) return "${(bytes / gb).toStringAsFixed(2)} GB";
  if (bytes >= mb) return "${(bytes / mb).toStringAsFixed(2)} MB";
  if (bytes >= kb) return "${(bytes / kb).toStringAsFixed(2)} KB";
  return "${bytes.toStringAsFixed(0)} B";
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _hivefyGreen.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: _hivefyGreen),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (next) {
              HapticFeedback.selectionClick();
              onChanged(next);
            },
            activeThumbColor: Colors.black,
            activeTrackColor: _hivefyGreen,
            inactiveTrackColor: Colors.white24,
            inactiveThumbColor: Colors.white54,
          ),
        ],
      ),
    );
  }
}

class _SettingsSliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final double value;
  final double min;
  final double max;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  const _SettingsSliderTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _hivefyGreen.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: _hivefyGreen),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      valueLabel,
                      style: const TextStyle(
                        color: _hivefyGreen,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _hivefyGreen,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: _hivefyGreen,
                    overlayColor: _hivefyGreen.withValues(alpha: 0.18),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
