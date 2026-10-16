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
/// Strategy (tried in order, first non-null wins):
///   1. Google Translate (`translate.googleapis.com`, `client=gtx`) — free,
///      no key, and crucially the ONLY engine here that understands Fongbe
///      ("fon"/Fon Gbe) and most African/source languages via `sl=auto`
///      source detection. This is what makes non-English lyrics actually
///      translate instead of spinning forever and showing nothing.
///   2. DeepL Free (api-free.deepl.com) — used when a valid API key is stored
///      in Settings. High quality for major languages, 500k chars/month free.
///   3. MyMemory (free, no key) — last-resort fallback.
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

/// What Google's `client=gtx` endpoint gives back: the translated block (null
/// when it is unusable) and the language it detected for the source.
typedef _GoogleOutcome = ({String? text, String? detected});

class LyricsTranslationService {
  static const String _myMemoryEndpoint =
      'https://api.mymemory.translated.net/get';
  static const String _deeplEndpoint = 'https://api-free.deepl.com/v2/translate';
  static const String _googleEndpoint =
      'https://translate.googleapis.com/translate_a/single';

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
    'Accept': '*/*',
  };

  static const String _deeplKeyBox = 'settings';
  static const String _deeplKeyField = 'deeplApiKey';

  /// Memoises Google's detected source language per lyric sample so opening the
  /// same player twice does not repeat the detection round-trip.
  static final Map<String, String?> _detectedLangCache = {};

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
  /// [targetLang] (a 2-letter code like "fr"). Tries Google (the only engine
  /// here that handles African / low-resource languages such as Fongbe via
  /// `sl=auto`), then DeepL when a key is present, then MyMemory. Returns null
  /// only when every engine fails.
  Future<String?> translateText(String text, String targetLang) async {
    final google = await _translateGoogle(text, targetLang);
    if (google != null) return google;
    final key = await getDeeplApiKey();
    if (key.isNotEmpty) {
      final deepl = await _translateDeepl(text, targetLang, key);
      if (deepl != null) return deepl;
    }
    return _translateMyMemory(text, targetLang);
  }

  /// Google's detected source language for [text], or null when Google cannot
  /// be reached. Used to skip translation when the lyrics are already written
  /// in the app's language — the user does not want a "translation" that is
  /// the same language as the line above it.
  ///
  /// Only a leading slice is sent: detection needs a few sentences, not the
  /// whole page, and lyric blocks can be several thousand characters.
  Future<String?> detectSourceLanguage(String text) async {
    final sample = _detectionSample(text);
    if (sample.isEmpty) return null;
    if (_detectedLangCache.containsKey(sample)) {
      return _detectedLangCache[sample];
    }
    final out = await _googleRaw(sample, 'en');
    final detected = out?.detected;
    // Bound the memo so a long session cannot grow it without limit.
    if (_detectedLangCache.length > 200) _detectedLangCache.clear();
    _detectedLangCache[sample] = detected;
    return detected;
  }

  static String _detectionSample(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.length > 1)
        .take(8)
        .join('\n');
    final src = lines.isEmpty ? text.trim() : lines;
    return src.length > 320 ? src.substring(0, 320) : src;
  }

  /// Google's unauthenticated `client=gtx` endpoint. `sl=auto` lets Google
  /// detect the source — the crucial part for Fongbe / Gbe lyrics, which
  /// DeepL and MyMemory simply do not support and therefore returned nothing.
  /// The translated segments are concatenated back in order, keeping the
  /// original "\n" line structure so the caller can realign per line.
  Future<String?> _translateGoogle(String text, String targetLang) async {
    final out = await _googleRaw(text, targetLang);
    return out?.text;
  }

  /// One request to Google's unauthenticated endpoint, returning both the
  /// translated block and the language Google detected for the source.
  Future<_GoogleOutcome?> _googleRaw(String text, String targetLang) async {
    final tl = targetLang.split('-').first.toLowerCase();
    try {
      final res = await http
          .get(
            Uri.parse(_googleEndpoint).replace(queryParameters: {
              'client': 'gtx',
              'sl': 'auto',
              'tl': tl,
              'dt': 't',
              'q': text,
            }),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! List || decoded.isEmpty) return null;
      final segments = decoded.first is List ? decoded.first as List : const [];
      final buffer = StringBuffer();
      for (final seg in segments) {
        final piece = (seg as List).isNotEmpty ? seg[0] : null;
        if (piece is String) buffer.write(piece);
      }
      final detected = _googleDetectedLang(decoded);
      final result = buffer.toString().trim();
      // A block that Google echoed back, or that is mostly the source text with
      // different casing/punctuation, is not a translation — and an error
      // payload is definitely not. Report the detection either way.
      final usable = result.isEmpty ||
              _looksLikeEngineError(result) ||
              _isNearEcho(text, result)
          ? null
          : result;
      return (text: usable, detected: detected);
    } catch (_) {
      return null;
    }
  }

  /// Which language Google thinks [text] is written in. Verified live against
  /// the endpoint: `client=gtx&dt=t` answers `[[segments], null, "fr", …]`, so
  /// the code sits at index 2 with index 1 empty (older shapes put it at 1, and
  /// the trailing `[…,["fr"],…]` list form is accepted too). This is what makes
  /// "no translation into the same language" work.
  static String? _googleDetectedLang(Object? decoded) {
    if (decoded is! List) return null;
    String? from(Object? v) {
      if (v is String && v.isNotEmpty) return v.toLowerCase();
      if (v is List && v.isNotEmpty && v.first is String) {
        final s = (v.first as String).trim();
        if (s.isNotEmpty) return s.toLowerCase();
      }
      return null;
    }

    for (final i in const [2, 1]) {
      if (i >= decoded.length) continue;
      final code = from(decoded[i]);
      if (code != null && code.length <= 8) return code;
    }
    return null;
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
      if (result == null ||
          result.isEmpty ||
          _looksLikeEngineError(result) ||
          _isNearEcho(text, result)) {
        return null;
      }
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
      // The API answers 200 even when the pair is unusable: it puts the
      // complaint ("'GB' IS AN INVALID TARGET LANGUAGE …", "PLEASE SELECT …")
      // inside responseData.translatedText. Rendering that as a lyric line is
      // exactly what the user saw, so check the status code it reports too.
      final status = body['responseStatus'];
      if (status is int && status != 200) return null;
      final translated =
          (body['responseData']?['translatedText'] as String?)?.trim();
      if (translated == null || translated.isEmpty) return null;
      final result = _stripHtml(translated);
      if (result.isEmpty ||
          _looksLikeEngineError(result) ||
          _isNearEcho(text, result)) {
        return null;
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  /// True when [text] is an engine error/quota payload rather than translated
  /// content. MyMemory, and occasionally DeepL proxies, return their complaint
  /// as the "translation" with an HTTP 200, so it must never reach the screen.
  static bool _looksLikeEngineError(String text) {
    final lower = text.toLowerCase();
    const markers = [
      'please select',
      'is an invalid',
      'invalid language',
      'invalid target',
      'invalid source',
      'langpair',
      'mymemory warning',
      'you used all available',
      'next available translation',
      'quota',
      'example: langpair',
      'almost all languages supported',
      'query length limit',
      'to report abuse',
      'having trouble accessing',
      'unauthorized',
      'invalid auth_key',
      'free plan',
    ];
    for (final m in markers) {
      if (lower.contains(m)) return true;
    }
    // An HTML fragment is never a lyric line (MyMemory wraps errors in <b>).
    return RegExp(r'<\s*/?\s*(b|i|p|br|a|div|span)\b', caseSensitive: false)
        .hasMatch(text);
  }

  static String _stripHtml(String text) =>
      text.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  /// True when [result] is really just [source] re-cased or lightly mangled.
  /// Engines do this for languages they do not translate (verified live:
  /// `en|ee` returned "I lOve yOu tOu tOo" for "I love you so much"), which the
  /// old exact-equality check let through as a bogus green lyric line.
  static bool _isNearEcho(String source, String result) {
    final a = _normalizeChars(source);
    final b = _normalizeChars(result);
    if (a.isEmpty || b.isEmpty) return a == b;
    if (a == b) return true;
    // A different script is a real translation, never an echo.
    if (_detectScriptStatic(source) != _detectScriptStatic(result)) {
      return false;
    }
    // Verified live: for a pair it does not know (`en|ee`) MyMemory returned
    // "I lOve yOu tOu tOo" for "I love you so much" — the SAME WORDS, re-cased
    // and mangled, which a character-similarity test alone misses. Half the
    // words still being the source's words is an echo, not a translation.
    final srcTokens = _tokens(source);
    final outTokens = _tokens(result);
    if (srcTokens.length >= 4 && outTokens.length >= 4) {
      final shared = outTokens.intersection(srcTokens).length;
      final shorter = srcTokens.length < outTokens.length
          ? srcTokens.length
          : outTokens.length;
      if (shared / shorter >= 0.60) return true;
    }
    return _bigramSimilarity(a, b) > 0.72;
  }

  static Set<String> _tokens(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((t) => t.isNotEmpty)
      .toSet();

  /// Keeps only letters and digits, lower-cased, so "Je t'aime." and
  /// "je t'aime" — or an Arabic line re-cased by an engine — compare equal.
  static String _normalizeChars(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  static String _detectScriptStatic(String text) {
    if (RegExp(r'[\p{Script=Arabic}]', unicode: true).hasMatch(text)) {
      return 'arab';
    }
    if (RegExp(r'[\p{Script=Cyrillic}]', unicode: true).hasMatch(text)) {
      return 'cyrl';
    }
    if (RegExp(r'[\p{Script=Han}]', unicode: true).hasMatch(text)) {
      return 'hani';
    }
    if (RegExp(r'[\p{Script=Devanagari}]', unicode: true).hasMatch(text)) {
      return 'deva';
    }
    return 'latin';
  }

  /// Sørensen–Dice coefficient over character bigrams, on 0..1.
  static double _bigramSimilarity(String a, String b) {
    if (a.length < 2 || b.length < 2) return a == b ? 1.0 : 0.0;
    final grams = <String, int>{};
    for (var i = 0; i < a.length - 1; i++) {
      final g = a.substring(i, i + 2);
      grams[g] = (grams[g] ?? 0) + 1;
    }
    var hits = 0;
    for (var i = 0; i < b.length - 1; i++) {
      final g = b.substring(i, i + 2);
      final left = grams[g] ?? 0;
      if (left > 0) {
        grams[g] = left - 1;
        hits++;
      }
    }
    return (2.0 * hits) / (a.length + b.length - 2);
  }

  /// True when both codes name the same language, ignoring region suffixes and
  /// the 3-letter (ISO 639-2/3) forms Google and MyMemory sometimes report.
  bool sameLanguage(String a, String b) {
    String norm(String code) {
      final base = code.toLowerCase().split('-').first.trim();
      return _langAliases[base] ?? base;
    }

    return norm(a).isNotEmpty && norm(a) == norm(b);
  }

  static const Map<String, String> _langAliases = {
    'fon': 'fo', // Fongbe (Gbe) — Google/MyMemory report "fon"
    'fra': 'fr',
    'fre': 'fr',
    'eng': 'en',
    'spa': 'es',
    'deu': 'de',
    'ger': 'de',
    'por': 'pt',
    'ita': 'it',
    'nld': 'nl',
    'dut': 'nl',
    'rus': 'ru',
    'ara': 'ar',
    'hin': 'hi',
    'ben': 'bn',
    'urd': 'ur',
    'tam': 'ta',
    'tel': 'te',
    'kan': 'kn',
    'mal': 'ml',
    'swa': 'sw',
    'yor': 'yo',
    'ibo': 'ig',
    'hau': 'ha',
    'ewe': 'ee',
    'twi': 'ak',
    'zul': 'zu',
    'sot': 'st',
    'nya': 'ny',
    'kon': 'kg',
    'lin': 'ln',
    'lua': 'lu',
    'check': 'en',
  };

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
  // Stop-word heuristics cannot tell two Latin-script languages apart reliably,
  // so ask Google which language the page is actually written in. If that is
  // the app language, translating would only produce the same language twice.
  final detected = await service.detectSourceLanguage(fullText);
  if (detected != null && service.sameLanguage(detected, targetLang)) {
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

/// Cache for translated free-form UI strings (About tagline, artist bio,
/// legal text), keyed by source text + target language.
final Map<String, String> _translatedTextCache = {};

/// Translates a free-form string into the app's currently selected language
/// using the same engines as lyrics (Google first, so Fongbe works), skipping
/// the round-trip when the text is already in the target language. This is how
/// the whole About screen and the Now Playing "About the artist" bio follow the
/// chosen language instead of staying stuck in French/English.
final translatedTextProvider =
    FutureProvider.family<String, ({String text})>((ref, key) async {
  final text = key.text;
  if (text.trim().isEmpty) return text;

  final lang = ref.watch(localeProvider).languageCode;
  final service = ref.watch(lyricsTranslationServiceProvider);
  if (service.isLikelyInLanguage(text, lang)) return text;

  final cacheKey = '$text::$lang';
  final hit = _translatedTextCache[cacheKey];
  if (hit != null) return hit;

  final out = await service.translateText(text, lang);
  final result = (out != null && out.trim().isNotEmpty) ? out : text;
  _translatedTextCache[cacheKey] = result;
  return result;
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
  var lines = trans.split('\n');
  // A line-count mismatch means the engine merged or dropped newlines and the
  // per-index realignment would be wrong. Re-translate line by line so every
  // lyric keeps its own correct translation (the "traduction complète" the
  // user wants, not a handful of lines that happened to stay aligned).
  if (lines.length != chunk.length) {
    lines = <String>[];
    for (final l in chunk) {
      final one = await service.translateText(l.text, targetLang);
      lines.add(one ?? l.text);
    }
  }
  for (var j = 0; j < chunk.length; j++) {
    final source = chunk[j].text.trim();
    final translated = j < lines.length ? lines[j].trim() : source;
    // Drop anything that is not an actual translation: the line unchanged (the
    // lyrics were already in the target language), an engine error payload, or
    // the source re-cased/mangled by an engine that does not know the language.
    if (translated.isEmpty ||
        _sameText(source, translated) ||
        LyricsTranslationService._looksLikeEngineError(translated) ||
        LyricsTranslationService._isNearEcho(source, translated)) {
      continue;
    }
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
