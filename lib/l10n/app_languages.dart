/// Supported application languages (locale code + display name + flag).
class AppLanguage {
  final String code;
  final String name;
  final String flag;

  const AppLanguage(this.code, this.name, this.flag);
}

/// Only languages with full translation tables in app_localizations.dart.
const List<AppLanguage> supportedLanguages = [
  AppLanguage('system', 'System', '\u{1F310}'),
  AppLanguage('en', 'English', '\u{1F1EC}\u{1F1E7}'),
  AppLanguage('fr', 'Français', '\u{1F1EB}\u{1F1F7}'),
  AppLanguage('fo', 'Fongbé', '\u{1F1E7}\u{1F1EF}'),
  AppLanguage('es', 'Español', '\u{1F1EA}\u{1F1F8}'),
  AppLanguage('de', 'Deutsch', '\u{1F1E9}\u{1F1EA}'),
  AppLanguage('pt', 'Português', '\u{1F1E7}\u{1F1F7}'),
  AppLanguage('it', 'Italiano', '\u{1F1EE}\u{1F1F9}'),
  AppLanguage('ru', 'Русский', '\u{1F1F7}\u{1F1FA}'),
  AppLanguage('ar', 'العربية', '\u{1F1F8}\u{1F1E6}'),
  AppLanguage('hi', 'हिन्दी', '\u{1F1EE}\u{1F1F3}'),
  AppLanguage('id', 'Bahasa Indonesia', '\u{1F1EE}\u{1F1E9}'),
  AppLanguage('vi', 'Tiếng Việt', '\u{1F1FB}\u{1F1F3}'),
  AppLanguage('tr', 'Türkçe', '\u{1F1F9}\u{1F1F7}'),
  AppLanguage('zh', '中文（简体）', '\u{1F1E8}\u{1F1F3}'),
];

/// Map of language code → native name (used as fallback display).
const Map<String, String> languageNativeNames = {
  'system': 'System',
  'en': 'English',
  'fr': 'Français',
  'fo': 'Fongbé',
  'es': 'Español',
  'de': 'Deutsch',
  'pt': 'Português',
  'it': 'Italiano',
  'ru': 'Русский',
  'ar': 'العربية',
  'hi': 'हिन्दी',
  'id': 'Bahasa Indonesia',
  'vi': 'Tiếng Việt',
  'tr': 'Türkçe',
  'zh': '中文（简体）',
};
