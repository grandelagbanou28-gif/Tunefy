import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  static const _bands = ['60', '230', '910', '3.6k', '14k'];
  static const _presets = {
    'Flat': [0, 0, 0, 0, 0],
    'Bass Boost': [8, 5, 2, 0, -2],
    'Treble': [-2, 0, 2, 5, 8],
    'Pop': [1, 3, 5, 3, 1],
    'Rock': [5, 3, -1, 3, 5],
    'Jazz': [4, 2, -2, 2, 4],
    'Classical': [5, 3, 0, 3, 5],
    'Electronic': [6, 4, 0, 2, 6],
  };

  late List<double> _values;
  String _selectedPreset = 'Flat';

  @override
  void initState() {
    super.initState();
    _values = List.filled(5, 0);
    _loadValues();
  }

  Future<void> _loadValues() async {
    try {
      final box = Hive.box('settings');
      final saved = box.get('eq_values');
      if (saved is List) {
        final loaded = saved.map((e) => (e as num).toDouble()).toList();
        if (loaded.length == 5) {
          _values = loaded.map((v) => v.clamp(-12.0, 12.0)).toList();
        }
        _selectedPreset = box.get('eq_preset', defaultValue: 'Flat');
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _saveValues() async {
    try {
      final box = Hive.box('settings');
      await box.put('eq_values', _values);
      await box.put('eq_preset', _selectedPreset);
    } catch (_) {}
  }

  void _applyPreset(String name) {
    final vals = _presets[name]!;
    setState(() {
      _selectedPreset = name;
      _values = vals.map((e) => e.toDouble()).toList();
    });
    _saveValues();
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 20),
                    onPressed: () => Navigator.pop(context),
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const Spacer(),
                  Text(
                    'Equalizer',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _buildBandSliders(context),
                    const SizedBox(height: 32),
                    Text(
                      'Presets',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildPresets(context),
                    const SizedBox(height: 160),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBandSliders(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(5, (i) {
          return _BandSlider(
            label: _bands[i],
            value: _values[i],
            onChanged: (v) {
              setState(() {
                _values[i] = v;
                _selectedPreset = 'Custom';
              });
              _saveValues();
            },
          );
        }),
      ),
    );
  }

  Widget _buildPresets(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _presets.entries.map((e) {
        final selected = _selectedPreset == e.key;
        return GestureDetector(
          onTap: () => _applyPreset(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF1DB954)
                  : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              e.key,
              style: TextStyle(
                color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _BandSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _BandSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${value > 0 ? '+' : ''}${value.round()}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: RotatedBox(
            quarterTurns: -1,
            child: Slider(
              value: value,
              min: -12,
              max: 12,
              divisions: 24,
              activeColor: const Color(0xFF1DB954),
              inactiveColor: Colors.white24,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
