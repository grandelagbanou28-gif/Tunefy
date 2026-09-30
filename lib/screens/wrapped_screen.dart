import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/services/listening_stats_service.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/utils/app_colors.dart';
import 'package:muzo/utils/format.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color _wrappedGreen = Color(0xFF1DDA63);
const Color _wrappedBg = Color(0xFF0A0F0B);

class WrappedScreen extends ConsumerStatefulWidget {
  const WrappedScreen({super.key});

  @override
  ConsumerState<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends ConsumerState<WrappedScreen> {
  static const String _yearPrefKey = 'wrapped_year';
  static const String _scopePrefKey = 'wrapped_all_time';
  static const int _cardCount = 6;

  static const List<List<Color>> _gradients = [
    [Color(0xFF04240F), Color(0xFF1DB954)],
    [Color(0xFF06130C), Color(0xFF1DDA63)],
    [Color(0xFF032019), Color(0xFF17C79B)],
    [Color(0xFF111F0B), Color(0xFF7ED957)],
    [Color(0xFF03170F), Color(0xFF2ED37F)],
    [Color(0xFF0B1A11), Color(0xFF1DB954)],
  ];

  final PageController _pageController = PageController();
  final List<GlobalKey> _cardKeys = List.generate(
    _cardCount,
    (_) => GlobalKey(),
  );

  int _year = DateTime.now().year;
  bool _allTime = false;
  int _page = 0;
  bool _sharing = false;
  late final ValueListenable<dynamic> _statsListenable;

  ListeningStatsService get _stats => ref.read(storageServiceProvider).stats;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _statsListenable = _stats.statsListenable;
    _statsListenable.addListener(_onStatsChanged);
    _restoreScope();
  }

  @override
  void dispose() {
    _statsListenable.removeListener(_onStatsChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onStatsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _restoreScope() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final now = DateTime.now().year;
    final savedYear = prefs.getInt(_yearPrefKey);
    setState(() {
      if (savedYear != null && savedYear == now) {
        _year = now;
        _allTime = prefs.getBool(_scopePrefKey) ?? false;
      } else {
        _year = now;
        _allTime = false;
      }
    });
  }

  void _setAllTime(bool value) {
    if (_allTime == value) return;
    setState(() => _allTime = value);
    final year = _year;
    final allTime = _allTime;
    unawaited(
      SharedPreferences.getInstance().then((prefs) {
        unawaited(prefs.setInt(_yearPrefKey, year));
        unawaited(prefs.setBool(_scopePrefKey, allTime));
      }),
    );
  }

  DateTime get _rangeStart => DateTime(_year, 1, 1);

  DateTime get _rangeEnd {
    final now = DateTime.now();
    return _year == now.year ? now : DateTime(_year + 1, 1, 1);
  }

  int get _minutes =>
      _allTime ? _stats.totalMinutes : _stats.minutesFor(_rangeStart, _rangeEnd);

  int get _songs =>
      _allTime ? _stats.totalSongs : _stats.songCountFor(_rangeStart, _rangeEnd);

  int get _artists => _allTime
      ? _stats.totalArtists
      : _stats.uniqueArtistsFor(_rangeStart, _rangeEnd);

  int get _albums =>
      _allTime ? _stats.totalAlbums : _stats.uniqueAlbumsFor(_rangeStart, _rangeEnd);

  bool get _hasData => _stats.totalSongs > 0;

  String _grouped(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  Future<void> _shareCurrentCard() async {
    if (_sharing) return;
    final l10n = _l10n;
    if (!_hasData) {
      showGlassSnackBar(context, l10n.nothingToShare, error: true);
      return;
    }
    setState(() => _sharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _cardKeys[_page].currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) {
          showGlassSnackBar(context, l10n.captureFailed, error: true);
        }
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        if (mounted) {
          showGlassSnackBar(context, l10n.captureFailed, error: true);
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/muzo_wrapped_$_page.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: l10n.shareText,
        subject: l10n.shareSubject,
      );
    } catch (e) {
      debugPrint('Wrapped share failed: $e');
      if (mounted) {
        showGlassSnackBar(context, l10n.shareFailed, error: true);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _wrappedBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child:
                  _hasData
                      ? PageView.builder(
                        controller: _pageController,
                        itemCount: _cardCount,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, index) => RepaintBoundary(
                          key: _cardKeys[index],
                          child: _buildCard(index),
                        ),
                      )
                      : _buildEmptyState(),
            ),
            if (_hasData) _buildIndicators(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.primaryText),
          ),
          Expanded(
            child: Center(
              child: _hasData ? _buildScopeSelector() : const SizedBox.shrink(),
            ),
          ),
          IconButton(
            onPressed: _sharing ? null : _shareCurrentCard,
            icon: const Icon(Icons.share, color: AppColors.primaryText),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeSelector() {
    final l10n = _l10n;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _scopeSegment(l10n.thisYear, !_allTime, false),
          _scopeSegment(l10n.allTime, _allTime, true),
        ],
      ),
    );
  }

  Widget _scopeSegment(String label, bool selected, bool value) {
    return GestureDetector(
      onTap: () => _setAllTime(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _wrappedGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildIndicators() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_cardCount, (i) {
          final active = i == _page;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: active ? _wrappedGreen : Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = _l10n;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note_rounded, color: _wrappedGreen, size: 64),
            const SizedBox(height: 18),
            Text(
              l10n.wrappedWaitingTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.primaryText,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.wrappedWaitingDesc,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildCard(int index) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradients[index],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 40).clamp(0.0, double.infinity),
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _cardContent(index),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _cardContent(int index) {
    final l10n = _l10n;
    switch (index) {
      case 0:
        return [
          _eyebrow(),
          const SizedBox(height: 18),
          _bigNumber(_grouped(_minutes)),
          const SizedBox(height: 8),
          _caption(l10n.minutesListened),
          const SizedBox(height: 18),
          _subLine(l10n.minutesTotal({'minutes': formatMinutes(_minutes)})),
          const SizedBox(height: 6),
          _subLine(
            _allTime
                ? l10n.minutesInYear({
                    'count': _grouped(_stats.minutesThisYear),
                    'year': '$_year',
                  })
                : l10n.minutesAllTime({
                    'count': _grouped(_stats.totalMinutes),
                  }),
          ),
        ];
      case 1:
        return [
          _eyebrow(),
          const SizedBox(height: 18),
          _bigNumber(_grouped(_songs)),
          const SizedBox(height: 8),
          _caption(l10n.songsPlayed),
          const SizedBox(height: 18),
          _subLine(
            _allTime
                ? l10n.songsInYear({
                    'count': _grouped(_stats.songsThisYear),
                    'year': '$_year',
                  })
                : l10n.songsAllTime({'count': _grouped(_stats.totalSongs)}),
          ),
        ];
      case 2:
        return [
          _eyebrow(),
          const SizedBox(height: 10),
          _caption(l10n.topArtists),
          const SizedBox(height: 4),
          _hint(l10n.top5AllTime),
          const SizedBox(height: 18),
          ..._rankRows(_stats.topArtists(5)),
        ];
      case 3:
        return [
          _eyebrow(),
          const SizedBox(height: 10),
          _caption(l10n.topSongs),
          const SizedBox(height: 4),
          _hint(l10n.top5AllTime),
          const SizedBox(height: 18),
          ..._rankRows(_stats.topSongs(5)),
        ];
      case 4:
        return [
          _eyebrow(),
          const SizedBox(height: 10),
          _caption(l10n.yourGenres),
          const SizedBox(height: 4),
          _hint(l10n.top5AllTime),
          const SizedBox(height: 20),
          ..._genreBars(_stats.topGenres(5)),
        ];
      default:
        return [
          _eyebrow(),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _statBlock(_grouped(_artists), l10n.artistsDiscovered),
              ),
              Container(
                width: 1,
                height: 92,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: Colors.white24,
              ),
              Expanded(
                child: _statBlock(_grouped(_albums), l10n.albumsDiscovered),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _subLine(
            _allTime
                ? l10n.songsInYear({
                    'count': _grouped(_stats.songsThisYear),
                    'year': '$_year',
                  })
                : l10n.songsAllTime({'count': _grouped(_stats.totalSongs)}),
          ),
        ];
    }
  }

  List<Widget> _rankRows(List<RankedItem> items) {
    if (items.isEmpty) {
      return [
        _EmptyRank(_l10n.noDataYet),
      ];
    }
    return [
      for (var i = 0; i < items.length; i++)
        _RankRow(
          rank: i + 1,
          item: items[i],
          playLabel: _l10n.playCount({'count': '${items[i].count}'}),
        ),
    ];
  }

  List<Widget> _genreBars(List<RankedItem> genres) {
    if (genres.isEmpty) {
      return [
        _EmptyRank(_l10n.noDataYet),
      ];
    }
    final maxCount = genres.first.count <= 0 ? 1 : genres.first.count;
    return [
      for (final genre in genres) ...[
        Row(
          children: [
            Expanded(
              child: Text(
                genre.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${genre.count}',
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: (genre.count / maxCount).clamp(0.04, 1.0),
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_wrappedGreen, _wrappedGreen.withValues(alpha: 0.35)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    ];
  }

  Widget _eyebrow() {
    final l10n = _l10n;
    return Text(
      _allTime ? l10n.wrapped : l10n.wrappedYear({'year': '$_year'}),
      style: const TextStyle(
        color: _wrappedGreen,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 3,
      ),
    );
  }

  Widget _bigNumber(String value) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        style: const TextStyle(
          color: AppColors.primaryText,
          fontSize: 88,
          fontWeight: FontWeight.w900,
          height: 1.0,
          letterSpacing: -2,
        ),
      ),
    );
  }

  Widget _caption(String value) {
    return Text(
      value,
      style: const TextStyle(
        color: AppColors.primaryText,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
    );
  }

  Widget _hint(String value) {
    return Text(
      value,
      style: const TextStyle(color: AppColors.secondaryText, fontSize: 13),
    );
  }

  Widget _subLine(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: AppColors.secondaryText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _statBlock(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 46,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.secondaryText,
            fontSize: 13,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  final int rank;
  final RankedItem item;
  final String playLabel;

  const _RankRow({
    required this.rank,
    required this.item,
    required this.playLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isFirst = rank == 1;
    return Padding(
      padding: EdgeInsets.only(bottom: isFirst ? 16 : 10),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '$rank',
              style: TextStyle(
                color: isFirst ? _wrappedGreen : Colors.white38,
                fontSize: isFirst ? 26 : 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.primaryText,
                fontSize: isFirst ? 20 : 16,
                fontWeight: isFirst ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            playLabel,
            maxLines: 1,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRank extends StatelessWidget {
  final String label;

  const _EmptyRank(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(color: AppColors.secondaryText, fontSize: 14),
    );
  }
}
