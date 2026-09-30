import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService();
});

/// Tunefy DJ — client Gemini (Freedify « AI & Smart Features »).
///
/// Used for Smart Playlist prompts, AI DJ tips, and taste-aware radio
/// hints. All responses are parsed as JSON; callers must fall back to
/// local heuristics on any failure (never invent tracks client-side).
class GeminiService {
  /// GEMINI_API_KEY — injectée au build via
  /// `--dart-define-from-file=secrets.json` (jamais commitée).
  static const String apiKey = String.fromEnvironment('GEMINI_API_KEY');

  // `gemini-2.0-flash` a été retiré par Google (404 « no longer available »).
  // Surchargeable au build via secrets.json → "GEMINI_MODEL".
  static const String _model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );
  static const Duration _timeout = Duration(seconds: 18);

  bool get isConfigured => apiKey.isNotEmpty;

  /// Raw text completion. Returns null on network/API/parse failure.
  Future<String?> completeText(String prompt) async {
    if (!isConfigured) return null;
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/'
        'models/$_model:generateContent?key=$apiKey',
      );
      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 1024,
          'responseMimeType': 'application/json',
        },
      });
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint('[Gemini] HTTP ${res.statusCode}: '
            '${res.body.substring(0, res.body.length.clamp(0, 200))}');
        return null;
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final candidates = json['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;
      final text = parts.first['text'] as String?;
      if (text == null || text.trim().isEmpty) return null;
      return text.trim();
    } catch (e) {
      debugPrint('[Gemini] completeText: $e');
      return null;
    }
  }

  /// Plain-text completion for conversational replies (no JSON constraint).
  Future<String?> completeProse(String prompt) async {
    if (!isConfigured) return null;
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/'
        'models/$_model:generateContent?key=$apiKey',
      );
      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 512,
        },
      });
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint('[Gemini] prose HTTP ${res.statusCode}');
        return null;
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final candidates = json['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;
      final text = parts.first['text'] as String?;
      if (text == null || text.trim().isEmpty) return null;
      return text.trim();
    } catch (e) {
      debugPrint('[Gemini] completeProse: $e');
      return null;
    }
  }

  /// Parses a JSON object (or JSON fenced in ```json) from a model reply.
  Map<String, dynamic>? parseJsonObject(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      s = s.replaceFirst(RegExp(r'\s*```$'), '');
    }
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    // Fallback: first {...} block
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final v = jsonDecode(s.substring(start, end + 1));
        if (v is Map<String, dynamic>) return v;
        if (v is Map) return Map<String, dynamic>.from(v);
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, dynamic>?> completeJson(String prompt) async {
    final text = await completeText(prompt);
    if (text == null) return null;
    return parseJsonObject(text);
  }
}
