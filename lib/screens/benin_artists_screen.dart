import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/models/benin_artist.dart';
import 'package:muzo/screens/artist_page_screen.dart';
import 'package:muzo/services/benin_catalog_service.dart';
import 'package:muzo/widgets/artist_avatar.dart';
import 'package:muzo/widgets/spotify_back_button.dart';
import 'package:muzo/widgets/spotify_chips.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

const Color _accentColor = Color(0xFF503750);
const String _allFilter = '__all__';

/// Browse the verified Benin artist catalog (Supabase `benin_artists`) with
/// category + text filtering. Tapping an artist opens her/his artist page.
class BeninArtistsScreen extends ConsumerStatefulWidget {
  const BeninArtistsScreen({super.key});

  @override
  ConsumerState<BeninArtistsScreen> createState() =>
      _BeninArtistsScreenState();
}

class _BeninArtistsScreenState extends ConsumerState<BeninArtistsScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = _allFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BeninArtist> _filtered(List<BeninArtist> artists) {
    final q = _searchController.text.trim().toLowerCase();
    return artists.where((a) {
      final catOk = _selectedCategory == _allFilter ||
          a.categories.contains(_selectedCategory);
      if (!catOk) return false;
      if (q.isEmpty) return true;
      return a.name.toLowerCase().contains(q) ||
          (a.country?.toLowerCase().contains(q) ?? false) ||
          a.categories.any((c) => c.toLowerCase().contains(q)) ||
          a.languages.any((l) => l.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalogAsync = ref.watch(beninCatalogProvider);
    final artists = catalogAsync.valueOrNull ?? const <BeninArtist>[];
    final isLoading = catalogAsync.isLoading && artists.isEmpty;
    final hasError = catalogAsync.hasError && artists.isEmpty;

    final counts = <String, int>{};
    for (final a in artists) {
      for (final c in a.categories) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    final categories = counts.keys.toList()
      ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
    final filtered = _filtered(artists);

    return Scaffold(
      backgroundColor: spotifyBlack,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  SpotifyBackButton(onPressed: () => Navigator.of(context).pop()),
                  const Spacer(),
                  Text(
                    artists.isEmpty ? '' : '${artists.length}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/covers/gospel.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0xE6503750),
                          Color(0x992C172C),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: spotifyWhite.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.people_alt_rounded,
                            color: spotifyWhite,
                            size: 34,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.beninArtistsTitle,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: spotifyWhite,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                artists.isEmpty
                                    ? l10n.beninVerifiedArtists
                                    : l10n.beninArtistsStats({
                                        'count': '${artists.length}',
                                        'verified':
                                            '${artists.where((a) => a.verified).length}',
                                      }),
                                style: TextStyle(
                                  color: spotifyWhite.withValues(alpha: 0.75),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: spotifyWhite),
                decoration: InputDecoration(
                  hintText: l10n.beninSearchHint,
                  hintStyle:
                      TextStyle(color: spotifyWhite.withValues(alpha: 0.4)),
                  prefixIcon: Icon(Icons.search,
                      color: spotifyWhite.withValues(alpha: 0.4)),
                  filled: true,
                  fillColor: spotifyWhite.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (categories.isNotEmpty)
              SizedBox(
                height: 56,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: categories.length + 1,
                  itemBuilder: (context, index) {
                    final isAll = index == 0;
                    final value = isAll ? _allFilter : categories[index - 1];
                    final label = isAll
                        ? l10n.all
                        : '$value (${counts[value]})';
                    final isSelected = _selectedCategory == value;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8, top: 10),
                      child: FilterChip(
                        label: Text(label),
                        selected: isSelected,
                        onSelected: (_) => setState(() {
                          _selectedCategory = value;
                        }),
                        selectedColor: _accentColor,
                        backgroundColor:
                            spotifyWhite.withValues(alpha: 0.1),
                        labelStyle: TextStyle(
                          color:
                              isSelected ? spotifyWhite : spotifyWhite.withValues(alpha: 0.8),
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ),
              ),
            Expanded(
              child: isLoading
                  ? const Center(
                      child: SpotifySpinner(color: _accentColor),
                    )
                  : hasError
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.beninCatalogError,
                                style: TextStyle(
                                  color: spotifyWhite.withValues(alpha: 0.7),
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () =>
                                    ref.invalidate(beninCatalogProvider),
                                child: Text(l10n.retry),
                              ),
                            ],
                          ),
                        )
                      : _buildList(filtered),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<BeninArtist> filtered) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final a = filtered[index];
        return _buildArtistTile(a);
      },
    );
  }

  Widget _buildArtistTile(BeninArtist a) {
    final subtitle = [
      if (a.country != null) a.country!,
      if (a.type.isNotEmpty && a.type != 'artist') a.type,
      ...a.categories,
    ].join(' • ');

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ArtistPageScreen(
              artistName: a.name,
              imageUrl: a.imageUrl,
              color: _accentColor,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: spotifyWhite.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ArtistAvatar(
              artistName: a.name,
              size: 52,
              imageUrl: a.imageUrl,
              circle: true,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: spotifyWhite,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (a.verified) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: Color(0xFF3D91F4),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: spotifyWhite,
                            size: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: spotifyWhite.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: spotifyWhite.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
