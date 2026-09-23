import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:muzo/models/dj_chat_models.dart';

final djChatHistoryServiceProvider = Provider<DjChatHistoryService>((ref) {
  return DjChatHistoryService();
});

/// Hive-backed chat history + generated mixes for Tunefy DJ.
///
/// Boxes:
/// - `dj_chat_history` — ordered list of [DjChatMessage] JSON (capped).
/// - `dj_generated_mixes` — map mixId → [DjGeneratedMix] JSON (capped).
class DjChatHistoryService {
  static const String _chatBoxName = 'dj_chat_history';
  static const String _mixBoxName = 'dj_generated_mixes';
  static const int maxMessages = 80;
  static const int maxMixes = 24;

  Box? _chatBox;
  Box? _mixBox;

  Future<Box> _openChat() async {
    if (_chatBox != null && _chatBox!.isOpen) return _chatBox!;
    _chatBox = await Hive.openBox(_chatBoxName);
    return _chatBox!;
  }

  Future<Box> _openMix() async {
    if (_mixBox != null && _mixBox!.isOpen) return _mixBox!;
    _mixBox = await Hive.openBox(_mixBoxName);
    return _mixBox!;
  }

  /// Loads chat messages oldest → newest.
  Future<List<DjChatMessage>> loadMessages() async {
    try {
      final box = await _openChat();
      final raw = box.get('messages');
      if (raw is! List) return const [];
      final out = <DjChatMessage>[];
      for (final m in raw) {
        if (m is Map) {
          try {
            out.add(DjChatMessage.fromJson(Map<String, dynamic>.from(m)));
          } catch (_) {}
        }
      }
      return out;
    } catch (e) {
      debugPrint('DjChatHistory loadMessages: $e');
      return const [];
    }
  }

  Future<void> saveMessages(List<DjChatMessage> messages) async {
    try {
      final box = await _openChat();
      final capped = messages.length > maxMessages
          ? messages.sublist(messages.length - maxMessages)
          : messages;
      await box.put(
        'messages',
        capped.map((m) => m.toJson()).toList(),
      );
    } catch (e) {
      debugPrint('DjChatHistory saveMessages: $e');
    }
  }

  Future<void> appendMessage(DjChatMessage message) async {
    final list = await loadMessages();
    list.add(message);
    await saveMessages(list);
  }

  Future<void> clearMessages() async {
    try {
      final box = await _openChat();
      await box.delete('messages');
    } catch (e) {
      debugPrint('DjChatHistory clearMessages: $e');
    }
  }

  Future<void> saveMix(DjGeneratedMix mix) async {
    try {
      final box = await _openMix();
      await box.put(mix.id, mix.toJson());
      await _pruneMixes(box);
    } catch (e) {
      debugPrint('DjChatHistory saveMix: $e');
    }
  }

  Future<DjGeneratedMix?> loadMix(String id) async {
    try {
      final box = await _openMix();
      final raw = box.get(id);
      if (raw is! Map) return null;
      return DjGeneratedMix.fromJson(Map<String, dynamic>.from(raw));
    } catch (e) {
      debugPrint('DjChatHistory loadMix: $e');
      return null;
    }
  }

  Future<List<DjGeneratedMix>> listMixes() async {
    try {
      final box = await _openMix();
      final out = <DjGeneratedMix>[];
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is Map) {
          try {
            out.add(DjGeneratedMix.fromJson(Map<String, dynamic>.from(raw)));
          } catch (_) {}
        }
      }
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    } catch (e) {
      debugPrint('DjChatHistory listMixes: $e');
      return const [];
    }
  }

  Future<void> deleteMix(String id) async {
    try {
      final box = await _openMix();
      await box.delete(id);
    } catch (e) {
      debugPrint('DjChatHistory deleteMix: $e');
    }
  }

  Future<void> _pruneMixes(Box box) async {
    if (box.length <= maxMixes) return;
    final entries = <DateTime, dynamic>{};
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) {
        final at =
            DateTime.tryParse(raw['createdAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
        entries[at] = key;
      }
    }
    final sortedKeys = entries.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final excess = box.length - maxMixes;
    for (var i = 0; i < excess && i < sortedKeys.length; i++) {
      await box.delete(sortedKeys[i].value);
    }
  }
}
