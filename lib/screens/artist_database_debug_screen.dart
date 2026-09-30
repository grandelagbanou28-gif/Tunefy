/// Debug screen for the artist database.
///
/// Local-only admin screen for viewing, searching, and editing artists.
/// Accessible from Settings > Debug > Artist Database.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/models/artist_record.dart';
import 'package:muzo/services/artist_database_service.dart';
import 'package:muzo/services/neon_database_service.dart' show EmbeddedSeedData;
import 'package:muzo/widgets/spotify_spinner.dart';
import 'package:muzo/l10n/app_localizations.dart';

const Color _bgColor = Color(0xFF121212);
const Color _green = Color(0xFF1DDA63);

class ArtistDatabaseDebugScreen extends ConsumerStatefulWidget {
  const ArtistDatabaseDebugScreen({super.key});

  @override
  ConsumerState<ArtistDatabaseDebugScreen> createState() =>
      _ArtistDatabaseDebugScreenState();
}

class _ArtistDatabaseDebugScreenState
    extends ConsumerState<ArtistDatabaseDebugScreen> {
  final _searchController = TextEditingController();
  List<ArtistRecord> _allArtists = [];
  List<ArtistRecord> _filteredArtists = [];
  String _selectedFilter = 'all';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadArtists();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadArtists() async {
    setState(() => _isLoading = true);
    try {
      final service = await ref.read(artistDatabaseServiceProvider.future);
      _allArtists = await service.local.getAllArtists();
      _filteredArtists = List.from(_allArtists);
    } catch (e) {
      debugPrint('Failed to load artists: $e');
      _allArtists = EmbeddedSeedData.artists;
      _filteredArtists = List.from(_allArtists);
    }
    setState(() => _isLoading = false);
  }

  void _applyFilter(String filter) {
    setState(() {
      _selectedFilter = filter;
      switch (filter) {
        case 'all':
          _filteredArtists = List.from(_allArtists);
          break;
        case 'confirmed':
          _filteredArtists = _allArtists.where((a) => a.isConfirmed).toList();
          break;
        case 'probable':
          _filteredArtists = _allArtists
              .where((a) => a.confidence == ConfidenceLevel.probable)
              .toList();
          break;
        default:
          _filteredArtists = _allArtists
              .where((a) =>
                  a.country.toLowerCase() == filter ||
                  a.genres.contains(filter) ||
                  a.subCategories
                      .any((s) => s.toLowerCase().contains(filter)))
              .toList();
      }
    });
  }

  void _searchArtists(String query) {
    if (query.isEmpty) {
      _applyFilter(_selectedFilter);
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _filteredArtists = _allArtists.where((a) {
        return a.name.toLowerCase().contains(q) ||
            a.id.toLowerCase().contains(q) ||
            a.aliases.any((alias) => alias.toLowerCase().contains(q)) ||
            a.country.toLowerCase().contains(q) ||
            a.genres.any((g) => g.toLowerCase().contains(q)) ||
            a.subCategories.any((s) => s.toLowerCase().contains(q));
      }).toList();
    });
  }

  Future<void> _addOrEditArtist({ArtistRecord? existing}) async {
    final result = await Navigator.push<ArtistRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => _ArtistEditScreen(existing: existing),
      ),
    );
    if (result != null) {
      final service = await ref.read(artistDatabaseServiceProvider.future);
      await service.local.saveArtist(result);
      await service.refresh();
      await _loadArtists();
    }
  }

  Future<void> _deleteArtist(ArtistRecord artist) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          l10n.artistDbDeleteTitle({'name': artist.name}),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          l10n.artistDbIrreversible,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final service = await ref.read(artistDatabaseServiceProvider.future);
      await service.local.deleteArtist(artist.id);
      await service.refresh();
      await _loadArtists();
    }
  }

  Future<void> _resetToSeed() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          l10n.artistDbResetTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          l10n.artistDbResetWarning(
              {'n': '${EmbeddedSeedData.artists.length}'}),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.artistDbReset,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final service = await ref.read(artistDatabaseServiceProvider.future);
      await service.local.resetToSeed();
      await service.refresh();
      await _loadArtists();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: Colors.white,
        title: Text(l10n.artistDatabase),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEditArtist(),
            tooltip: l10n.artistDbAddArtist,
          ),
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: _resetToSeed,
            tooltip: l10n.artistDbResetTooltip,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadArtists,
            tooltip: l10n.artistDbRefresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: SpotifySpinner(color: _green))
          : Column(
              children: [
                _buildStats(),
                _buildSearchBar(),
                _buildFilterChips(),
                Expanded(child: _buildArtistList()),
              ],
            ),
    );
  }

  Widget _buildStats() {
    final l10n = AppLocalizations.of(context);
    final confirmed = _allArtists.where((a) => a.isConfirmed).length;
    final probable =
        _allArtists.where((a) => a.confidence == ConfidenceLevel.probable).length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('${_allArtists.length}', l10n.artistDbStatTotal),
          _statItem('$confirmed', l10n.artistDbStatConfirmed),
          _statItem('$probable', l10n.artistDbStatProbable),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: _green,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _searchController,
        onChanged: _searchArtists,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: l10n.artistDbSearchHint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.4)),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final l10n = AppLocalizations.of(context);
    final filters = [
      ('all', l10n.artistDbFilterAll),
      ('confirmed', l10n.artistDbStatConfirmed),
      ('probable', l10n.artistDbStatProbable),
      ('benin', l10n.artistDbFilterBenin),
      ('gospel', 'Gospel'),
      ('rap', 'Rap'),
      ('afrobeats', 'Afrobeats'),
    ];

    return Container(
      height: 56,
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final (value, label) = filters[index];
          final isSelected = _selectedFilter == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) => _applyFilter(value),
              selectedColor: _green,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              labelStyle: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildArtistList() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.artistDbArtistsCount({'n': '${_filteredArtists.length}'}),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredArtists.length,
              itemBuilder: (context, index) {
                final artist = _filteredArtists[index];
                return _buildArtistTile(artist);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtistTile(ArtistRecord artist) {
    final isConfirmed = artist.isConfirmed;
    final confColor = isConfirmed ? Colors.green : Colors.orange;

    return Dismissible(
      key: ValueKey(artist.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete, color: Colors.red),
      ),
      confirmDismiss: (_) async {
        await _deleteArtist(artist);
        return false;
      },
      child: GestureDetector(
        onTap: () => _addOrEditArtist(existing: artist),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: confColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    artist.name.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: confColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          artist.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: confColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            artist.confidence.displayName,
                            style: TextStyle(
                              color: confColor,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${artist.country} • ${artist.genres.join(", ")}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                    if (artist.subCategories.isNotEmpty)
                      Text(
                        artist.subCategories.join(", "),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (artist.aliases.isNotEmpty)
                Icon(
                  Icons.alternate_email,
                  color: Colors.white.withValues(alpha: 0.3),
                  size: 16,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistEditScreen extends StatefulWidget {
  final ArtistRecord? existing;

  const _ArtistEditScreen({this.existing});

  @override
  State<_ArtistEditScreen> createState() => _ArtistEditScreenState();
}

class _ArtistEditScreenState extends State<_ArtistEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _aliasesController;
  late final TextEditingController _countryController;
  late final TextEditingController _genresController;
  late final TextEditingController _subCategoriesController;
  late final TextEditingController _sourcesController;
  late ConfidenceLevel _confidence;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _aliasesController =
        TextEditingController(text: e?.aliases.join(', ') ?? '');
    _countryController = TextEditingController(text: e?.country ?? '');
    _genresController =
        TextEditingController(text: e?.genres.join(', ') ?? '');
    _subCategoriesController =
        TextEditingController(text: e?.subCategories.join(', ') ?? '');
    _sourcesController =
        TextEditingController(text: e?.sources.join(', ') ?? '');
    _confidence = e?.confidence ?? ConfidenceLevel.confirmed;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aliasesController.dispose();
    _countryController.dispose();
    _genresController.dispose();
    _subCategoriesController.dispose();
    _sourcesController.dispose();
    super.dispose();
  }

  String _slugify(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now().toIso8601String();
    final name = _nameController.text.trim();
    final id = widget.existing?.id ?? _slugify(name);

    final record = ArtistRecord(
      id: id,
      name: name,
      aliases: _split(_aliasesController.text),
      country: _countryController.text.trim(),
      genres: _split(_genresController.text),
      subCategories: _split(_subCategoriesController.text),
      confidence: _confidence,
      sources: _split(_sourcesController.text),
      dateAdded: widget.existing?.dateAdded ?? now,
      dateLastVerified: now,
    );

    Navigator.pop(context, record);
  }

  List<String> _split(String text) {
    return text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEditing = widget.existing != null;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        foregroundColor: Colors.white,
        title: Text(isEditing ? l10n.artistDbEditTitle : l10n.artistDbNewTitle),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              l10n.save,
              style: const TextStyle(
                  color: _green, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(_nameController, l10n.artistDbFieldName,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? l10n.artistDbRequired : null),
              const SizedBox(height: 12),
              _buildTextField(
                  _aliasesController, l10n.artistDbFieldAliases),
              const SizedBox(height: 12),
              _buildTextField(_countryController, l10n.artistDbFieldCountry,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? l10n.artistDbRequired : null),
              const SizedBox(height: 12),
              _buildTextField(
                  _genresController, l10n.artistDbFieldGenres),
              const SizedBox(height: 12),
              _buildTextField(_subCategoriesController,
                  l10n.artistDbFieldSubCategories),
              const SizedBox(height: 12),
              _buildTextField(
                  _sourcesController, l10n.artistDbFieldSources),
              const SizedBox(height: 20),
              Text(
                l10n.artistDbConfidenceLevel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildConfidenceToggle(
                    label: l10n.artistDbConfidenceConfirmed,
                    value: ConfidenceLevel.confirmed,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 12),
                  _buildConfidenceToggle(
                    label: l10n.artistDbStatProbable,
                    value: ConfidenceLevel.probable,
                    color: Colors.orange,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _buildConfidenceToggle({
    required String label,
    required ConfidenceLevel value,
    required Color color,
  }) {
    final isSelected = _confidence == value;
    return GestureDetector(
      onTap: () => setState(() => _confidence = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.5),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
