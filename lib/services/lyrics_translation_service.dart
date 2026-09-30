import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/services/lyrics_service.dart';

/// Translates lyric lines into the app's selected language so the player can
/// show a live, scrolling translation below each active line.
///
/// Strategy:
///   1. DeepL Free (api-free.deepl.com) — used when a valid API key is stored
///      in Settings. High quality, 500k chars/month free, no billing card.
///   2. MyMemory (free, no key) — automatic fallback when no DeepL key is
///      configured or when the DeepL request fails.
///
/// Translations are cached per (song, target-lang) so it only costs one
/// network round-trip the first time a lyric page is opened.
class TranslatedLyricLine {
  final int index;
  final String text;
  const TranslatedLyricLine(this.index, this.text);
}

final lyricsTranslationServiceProvider =
    Provider((ref) => LyricsTranslationService());

class LyricsTranslationService {
  static const String _myMemoryEndpoint =
      'https://api.mymemory.translated.net/get';
  static const String _deeplEndpoint = 'https://api-free.deepl.com/v2/translate';

  static const String _deeplKeyBox = 'settings';
  static const String _deeplKeyField = 'deeplApiKey';
  static const String _builtinDeeplKeyEncoded =
      '99~51~51~101~52~97~101~98~120~51~49~102~48~120~97~48~55~98~120~52~101~96~55~120~51~52~99~103~54~101~48~99~54~98~54~99~111~51~45';

  static const String _maskPrefix = 'd1:';
  static const int _maskSalt = 0x55;

  static String _decodeKey(String encoded) {
    final buffer = StringBuffer();
    for (final part in encoded.split('~')) {
      final n = int.tryParse(part);
      if (n == null) continue;
      buffer.writeCharCode(n ^ _maskSalt);
    }
    return buffer.toString();
  }

  static String _encodeKey(String key) =>
      key.codeUnits.map((c) => (c ^ _maskSalt).toString()).join('~');

  static String _maskKey(String key) => '$_maskPrefix${_encodeKey(key)}';

  static String? _unmaskStored(String stored) {
    if (stored.isEmpty) return null;
    if (stored.startsWith(_maskPrefix)) {
      try {
        return _decodeKey(stored.substring(_maskPrefix.length));
      } catch (_) {
        return null;
      }
    }
    return stored;
  }

  static String get _builtinDeeplKey => _decodeKey(_builtinDeeplKeyEncoded);

  /// Reads the stored translation key, or null when none was saved. Never
  /// returns the built-in fallback, so the settings screen stays blank until
  /// the user actually stores a key.
  Future<String?> getStoredDeeplApiKey() async {
    try {
      final box = Hive.isBoxOpen(_deeplKeyBox)
          ? Hive.box(_deeplKeyBox)
          : await Hive.openBox(_deeplKeyBox);
      final stored = (box.get(_deeplKeyField) as String?)?.trim() ?? '';
      return _unmaskStored(stored);
    } catch (_) {
      return null;
    }
  }

  /// Reads the stored translation key. Falls back to the built-in (obfuscated)
  /// key so translation works out-of-the-box without requiring configuration.
  Future<String> getDeeplApiKey() async {
    final stored = await getStoredDeeplApiKey();
    if (stored != null && stored.isNotEmpty) return stored;
    return _builtinDeeplKey;
  }

  /// Persists the translation key, obfuscated at rest so it is not readable as
  /// plain text in the app's on-disk settings.
  Future<void> setDeeplApiKey(String key) async {
    try {
      final box = Hive.isBoxOpen(_deeplKeyBox)
          ? Hive.box(_deeplKeyBox)
          : await Hive.openBox(_deeplKeyBox);
      await box.put(_deeplKeyField, _maskKey(key.trim()));
    } catch (_) {}
  }

  Future<void> clearDeeplApiKey() async {
    try {
      final box = Hive.isBoxOpen(_deeplKeyBox)
          ? Hive.box(_deeplKeyBox)
          : await Hive.openBox(_deeplKeyBox);
      await box.delete(_deeplKeyField);
    } catch (_) {}
  }

  /// Translates [text] (may contain multiple lines separated by "\n") into
  /// [targetLang] (a 2-letter code like "fr"). Tries DeepL first when a key is
  /// present, then falls back to MyMemory. Returns null when it fails.
  Future<String?> translateText(String text, String targetLang) async {
    final key = await getDeeplApiKey();
    if (key.isNotEmpty) {
      final deepl = await _translateDeepl(text, targetLang, key);
      if (deepl != null) return deepl;
    }
    return _translateMyMemory(text, targetLang);
  }

  Future<String?> _translateDeepl(
      String text, String targetLang, String apiKey) async {
    try {
      final uri = Uri.parse(_deeplEndpoint);
      final target = _deeplLang(targetLang);
      final res = await http
          .post(
            uri,
            headers: {
              'Authorization': 'DeepL-Auth-Key $apiKey',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: 'text=${Uri.encodeComponent(text)}&target_lang=$target',
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final body = json.decode(res.body);
      final translated =
          (body['translations'] as List?)?.first['text'] as String?;
      final result = translated?.trim();
      if (result == null || result.isEmpty || result == text) return null;
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _translateMyMemory(
      String text, String targetLang) async {
    // MyMemory does NOT accept "auto" as the source language, so we must
    // detect the source ourselves and send it explicitly (e.g. `en|fr`).
    final source = _detectSourceLang(text);
    final q = Uri.encodeComponent(text);
    final uri =
        Uri.parse('$_myMemoryEndpoint?q=$q&langpair=$source|$targetLang');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = json.decode(res.body);
      final translated =
          (body['responseData']?['translatedText'] as String?)?.trim();
      if (translated == null || translated.isEmpty) return null;
      if (translated == text) return null;
      return translated;
    } catch (_) {
      return null;
    }
  }

  /// Best-effort source-language detection needed by MyMemory (it rejects the
  /// "auto" source). Script-based for non-Latin languages (reliable) and
  /// stop-word based for Latin ones; falls back to "en" when unsure.
  String _detectSourceLang(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'en';

    final script = _detectScript(trimmed);
    switch (script) {
      case 'arab':
        return 'ar';
      case 'cyrl':
        return 'ru';
      case 'deva':
        return 'hi';
      case 'hani':
        return 'zh';
    }

    // Latin: pick the language whose stop-word list matches the most tokens.
    final lower = trimmed.toLowerCase();
    final tokens = RegExp(r"[a-zà-ÿ']+").allMatches(lower).map((m) => m.group(0)).toList();
    if (tokens.length < 4) return 'en';
    String? best;
    var bestHits = -1;
    for (final code in const ['en', 'es', 'de', 'pt', 'it', 'fr']) {
      final stop = _stopwords(code);
      if (stop == null) continue;
      var hits = 0;
      for (final t in tokens) {
        if (stop.contains(t)) hits++;
      }
      if (hits > bestHits) {
        bestHits = hits;
        best = code;
      }
    }
    // Only trust a language that matches at least a couple of tokens.
    return (best != null && bestHits >= 2) ? best : 'en';
  }

  /// Map a 2-letter app language code to DeepL's expected language code.
  String _deeplLang(String lang) {
    final code = lang.split('-').first.toLowerCase();
    const map = {
      'zh': 'ZH',
      'pt': 'PT-PT', // DeepL requires PT-PT or PT-BR
    };
    if (map.containsKey(code)) return map[code]!;
    return code.toUpperCase();
  }

  /// Signals that a text is already (likely) in [targetLang] and should not be
  /// translated. For non-Latin scripts (AR/RU/HI/ZH) this is decided by script
  /// detection, which is reliable. For Latin-script languages (FR/EN/ES/DE/PT/
  /// IT/...) script detection is useless, so here we only skip translation when
  /// the lyrics are OVERWHELMINGLY full of target-language stop-words. This is a
  /// best-effort short-circuit to avoid pointless network calls — the real
  /// safety net is `_doTranslate`, which drops any translated line that comes
  /// back identical to the source (i.e. it was already in the target language).
  bool isLikelyInLanguage(String text, String targetLang) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final code = targetLang.split('-').first;

    final expectedScript = switch (code) {
      'ar' => 'arab',
      'ru' => 'cyrl',
      'hi' => 'deva',
      'zh' => 'hani',
      _ => 'latin',
    };
    if (expectedScript != 'latin') {
      return _detectScript(trimmed) == expectedScript;
    }

    final stop = _stopwords(code);
    if (stop == null || stop.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    final tokens =
        RegExp(r"[a-zà-ÿ']+").allMatches(lower).map((m) => m.group(0)).toList();
    if (tokens.length < 8) return false;
    var hits = 0;
    for (final t in tokens) {
      if (stop.contains(t)) hits++;
    }
    // High bar: only skip when it is unmistakably the target language.
    return hits / tokens.length >= 0.30;
  }

  /// Rough script tag (arab/cyrl/deva/hani/latin) for [text].
  String _detectScript(String text) {
    final t = text;
    if (RegExp(r'[\p{Script=Arabic}\u0600-\u06FF]', unicode: true).hasMatch(t)) {
      return 'arab';
    }
    if (RegExp(r'[\p{Script=Cyrillic}\u0400-\u04FF]', unicode: true).hasMatch(t)) {
      return 'cyrl';
    }
    if (RegExp(r'[\p{Script=Devanagari}\u0900-\u097F]', unicode: true).hasMatch(t)) {
      return 'deva';
    }
    if (RegExp(r'[\p{Script=Han}\u4E00-\u9FFF]', unicode: true).hasMatch(t)) {
      return 'hani';
    }
    return 'latin';
  }

  /// Small common stop-word list per supported Latin language, used to decide
  /// whether lyrics are already written in that language. Returns null when the
  /// target has no list (→ we always translate).
  Set<String>? _stopwords(String code) {
    const lists = <String, Set<String>>{
      'fr': {
        'je', 'tu', 'il', 'elle', 'nous', 'vous', 'ils', 'elles', 'on', 'ne',
        'le', 'la', 'les', 'un', 'une', 'des', 'de', 'du', 'et', 'ou', 'mais',
        'que', 'qui', 'quoi', 'dans', 'pour', 'avec', 'sur', 'ce', 'cet',
        'cette', 'mes', 'tes', 'ses', 'mon', 'ton', 'son', 'notre', 'votre',
        'leur', 'me', 'te', 'se', 'moi', 'toi', 'lui', 'est', 'suis',
        'es', 'être', 'aussi', 'pas', 'tout', 'tous', 'au', 'aux',
      },
      'en': {
        'the', 'a', 'an', 'and', 'of', 'to', 'in', 'is', 'are', 'was', 'were',
        'i', 'you', 'he', 'she', 'it', 'we', 'they', 'my', 'your', 'this',
        'that', 'for', 'with', 'on', 'at', 'be', 'have', 'has', 'not', 'but',
        'me', 'him', 'her', 'us', 'them', 'so', 'do', 'don', 'just', 'know',
      },
      'es': {
        'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'y', 'o', 'de',
        'en', 'que', 'no', 'me', 'te', 'se', 'mi', 'tu', 'su', 'nuestro',
        'para', 'con', 'por', 'como', 'más', 'hay', 'esto', 'ese', 'aquí',
        'eres', 'está', 'estoy', 'toda', 'todo', 'nos', 'les', 'lo', 'al',
      },
      'de': {
        'der', 'die', 'das', 'ein', 'eine', 'und', 'oder', 'ist', 'sind',
        'ich', 'du', 'er', 'sie', 'wir', 'ihr', 'mich', 'dich', 'nicht',
        'noch', 'mit', 'für', 'auf', 'von', 'zu', 'im', 'am', 'da', 'wenn',
        'hab', 'hast', 'hat', 'mein', 'dein', 'sein', 'alle', 'wie',
      },
      'pt': {
        'o', 'a', 'os', 'as', 'um', 'uma', 'e', 'ou', 'de', 'do', 'da', 'em',
        'no', 'na', 'que', 'não', 'me', 'te', 'se', 'meu', 'minha', 'seu',
        'sua', 'para', 'com', 'por', 'como', 'tem', 'está', 'sou', 'é', 'tudo',
        'todo', 'nós', 'eles', 'elas', 'eu', 'tu', 'voce', 'você',
      },
      'it': {
        'il', 'lo', 'la', 'i', 'gli', 'le', 'un', 'uno', 'una', 'e', 'o', 'di',
        'del', 'della', 'in', 'che', 'non', 'mi', 'ti', 'si', 'mio', 'tuo',
        'suo', 'per', 'con', 'come', 'è', 'sono', 'sei', 'tutto', 'tutti',
        'io', 'tu', 'noi', 'voi', 'lui', 'lei', 'sta',
      },
    };
    return lists[code];
  }

  /// Map our app language code(s) handled together — "zh_TW" -> "zh-TW".
  String normalizeTarget(String lang) => lang.replaceAll('_', '-');
}

/// Async translation cache used by the translated-lines provider.
final Map<String, Future<List<TranslatedLyricLine>?>?> _translatedCache = {};

/// Produces the translated, time-aligned lines for a song. Returns null when
/// translation is not needed (source already in the app language) or failed.
final translatedLyricsProvider =
    FutureProvider.autoDispose.family<List<TranslatedLyricLine>?, String>(
        (ref, videoId) async {
  final lyricsAsync = ref.watch(currentLyricsProvider(videoId));
  final lyrics = lyricsAsync.valueOrNull;
  if (lyrics == null) return null;

  final targetLang = ref.watch(localeProvider).languageCode;
  final service = ref.watch(lyricsTranslationServiceProvider);

  final timed = parseTimedLyrics(lyrics, Duration.zero);
  if (timed.isEmpty) return null;

  final fullText = timed.map((l) => l.text).join('\n');
  // When the lyrics are already in the app/system language, there is nothing to
  // translate — return null so no green duplicate is shown.
  if (service.isLikelyInLanguage(fullText, targetLang)) {
    return null;
  }

  final cacheKey = '$videoId::$targetLang';
  if (_translatedCache.containsKey(cacheKey)) {
    return _translatedCache[cacheKey];
  }

  final future = _doTranslate(service, timed, targetLang);
  _translatedCache[cacheKey] = future;
  // Do not keep failed (null) results cached: evict them so a later watch
  // re-attempts the translation instead of being stuck showing no green lines.
  future.then<void>((result) {
    if (result == null) _translatedCache.remove(cacheKey);
  }).catchError((_) {
    _translatedCache.remove(cacheKey);
  });
  return future;
});

Future<List<TranslatedLyricLine>?> _doTranslate(
  LyricsTranslationService service,
  List<TimedLyricLine> timed,
  String targetLang,
) async {
  final results = <TranslatedLyricLine>[];

  // MyMemory's free tier caps each request at ~500 characters, so grouping by a
  // fixed line count would exceed the limit and translation would fail. Group
  // lines by total character count instead, keeping the original global index
  // so the translations stay time-aligned with their source lines.
  const maxChars = 450;
  var chunk = <TimedLyricLine>[];
  var chunkChars = 0;

  for (var i = 0; i < timed.length; i++) {
    final line = timed[i];
    final len = line.text.length + 1; // +1 for the "\n" separator
    if (chunk.isNotEmpty && chunkChars + len > maxChars) {
      await _translateChunk(service, chunk, i - chunk.length, targetLang, results);
      chunk = <TimedLyricLine>[];
      chunkChars = 0;
    }
    chunk.add(line);
    chunkChars += len;
  }
  if (chunk.isNotEmpty) {
    await _translateChunk(
        service, chunk, timed.length - chunk.length, targetLang, results);
  }

  return results.isEmpty ? null : results;
}

Future<void> _translateChunk(
  LyricsTranslationService service,
  List<TimedLyricLine> chunk,
  int startIndex,
  String targetLang,
  List<TranslatedLyricLine> out,
) async {
  final chunkText = chunk.map((l) => l.text).join('\n');
  final trans = await service.translateText(chunkText, targetLang);
  if (trans == null) return;
  final lines = trans.split('\n');
  for (var j = 0; j < chunk.length; j++) {
    final source = chunk[j].text.trim();
    final translated = j < lines.length ? lines[j].trim() : source;
    // Safety net: if the "translation" is identical to the original, the
    // lyrics were already in the target language — omit the line so the UI
    // does not show a pointless green copy of the same text.
    if (translated.isEmpty || _sameText(source, translated)) continue;
    out.add(TranslatedLyricLine(startIndex + j, translated));
  }
}

/// Loose equality used to drop lines the translator returned unchanged. Ignores
/// case and trailing punctuation so "Je t'aime." vs "je t'aime" count as equal.
bool _sameText(String a, String b) {
  if (a == b) return true;
  final ca = a.toLowerCase().replaceAll(RegExp(r'[\s.,!?;:…\-]+'), '');
  final cb = b.toLowerCase().replaceAll(RegExp(r'[\s.,!?;:…\-]+'), '');
  return ca == cb;
}
