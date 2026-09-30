import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_languages.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/widgets/spotify_search_bar.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

const Color hivefyBg = Color(0xFF121212);
const Color hivefyGreen = Color(0xFF1DDA63);

Color _darkerGreen(Color color, {double darkenFactor = 0.18}) {
  final hsl = HSLColor.fromColor(color);
  final newLight = (hsl.lightness - darkenFactor).clamp(0.12, 1.0);
  final newSat = (hsl.saturation + 0.1).clamp(0.0, 1.0);
  return hsl.withLightness(newLight).withSaturation(newSat).toColor();
}

class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  bool _isTitleCollapsed = false;
  late ScrollController _scrollController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()
      ..addListener(() {
        final offset = _scrollController.offset;
        if (offset > 120 && !_isTitleCollapsed) {
          setState(() => _isTitleCollapsed = true);
        } else if (offset <= 120 && _isTitleCollapsed) {
          setState(() => _isTitleCollapsed = false);
        }
      });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<AppLanguage> get _visibleLanguages {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return supportedLanguages;
    return supportedLanguages.where((l) {
      return l.code.toLowerCase().contains(q) ||
          l.name.toLowerCase().contains(q) ||
          (languageNativeNames[l.code] ?? '')
              .toLowerCase()
              .contains(q);
    }).toList();
  }

  String _displayName(AppLanguage lang) {
    return languageNativeNames[lang.code] ?? lang.name;
  }

  Future<void> _applyLanguage(String code) async {
    final storage = ref.read(storageServiceProvider);
    if (code == storage.appLanguage) {
      ref.read(localeProvider.notifier).state = _localeFromCode(code);
      return;
    }
    setState(() => _applying = true);
    await storage.setAppLanguage(code);
    ref.read(localeProvider.notifier).state = _localeFromCode(code);
    if (mounted) setState(() => _applying = false);
  }

  Locale _localeFromCode(String code) {
    if (code.contains('_')) {
      final parts = code.split('_');
      return Locale(parts[0], parts.length > 1 ? parts[1] : null);
    }
    return Locale(code);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentLang = ref.watch(storageServiceProvider).appLanguage;
    final visible = _visibleLanguages;

    return Scaffold(
      backgroundColor: hivefyBg,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              _buildAppBar(context, l10n),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.selectLanguage,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SpotifySearchBar(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v),
                        hintText: l10n.searchLanguage,
                        height: 44,
                      ),
                    ],
                  ),
                ),
              ),
              if (visible.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        l10n.noLanguageFound,
                        style: const TextStyle(color: Colors.white38),
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final lang = visible[index];
                    final isSelected = currentLang == lang.code;
                    return InkWell(
                      onTap: () {
                        if (!_applying) _applyLanguage(lang.code);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Text(
                              lang.flag,
                              style: const TextStyle(fontSize: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lang.name,
                                    style: TextStyle(
                                      color: isSelected ? hivefyGreen : Colors.white,
                                      fontSize: 15,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (lang.name != _displayName(lang))
                                    Text(
                                      _displayName(lang),
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle,
                                  color: hivefyGreen, size: 20),
                          ],
                        ),
                      ),
                    );
                  }, childCount: visible.length),
                ),
              if (!_applying &&
                  currentLang.isNotEmpty &&
                  visible.any((l) => l.code == currentLang))
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
          if (_applying)
            Container(
              color: hivefyBg.withValues(alpha: 0.95),
              child: const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: SpotifySpinner(
                    strokeWidth: 3,
                    color: hivefyGreen,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, AppLocalizations l10n) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 160,
      backgroundColor: _darkerGreen(hivefyGreen),
      leading: const BackButton(color: Colors.white),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final rawCollapse = (constraints.maxHeight - kToolbarHeight) / 80.0;
          final collapsePercent = rawCollapse.clamp(0.0, 1.0);
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
                l10n.language,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_darkerGreen(hivefyGreen), hivefyBg],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 32),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Opacity(
                    opacity: 0.95 * collapsePercent,
                    child: Text(
                      l10n.language,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 28,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
