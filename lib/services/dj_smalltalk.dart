import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/services/dj_mood_bot.dart';

/// Conversation du Tunefy DJ quand Gemini n'est pas joignable (hors-ligne,
/// clé absente, appel raté). Règles FR + EN sur le texte normalisé, réponses
/// localisées : le DJ parle, pose une question en retour, mais ne cite jamais
/// un titre ou un artiste.
class DjSmallTalk {
  const DjSmallTalk._();

  /// Créneau de salutation : une seule fois par matinée / après-midi / soirée /
  /// nuit, clé stockée en session (`2026-10-11:afternoon`).
  static String slotKey(DateTime now) =>
      '${now.year}-${now.month}-${now.day}-${_slot(now)}';

  static String _slot(DateTime now) {
    if (now.hour >= 5 && now.hour < 12) return 'morning';
    if (now.hour >= 12 && now.hour < 18) return 'afternoon';
    if (now.hour >= 18 && now.hour < 23) return 'evening';
    return 'night';
  }

  /// Salut selon l'heure et demande comment la journée se passe.
  static String greeting(AppLocalizations l10n, {DateTime? at}) {
    final now = at ?? DateTime.now();
    switch (_slot(now)) {
      case 'morning':
        return l10n.djGreetMorning;
      case 'afternoon':
        return l10n.djGreetAfternoon;
      case 'evening':
        return l10n.djGreetEvening;
      default:
        return l10n.djGreetNight;
    }
  }

  /// Réponse locale à un message qui ne décrit aucune humeur.
  static String reply(AppLocalizations l10n, String raw) {
    final t = DjMoodBot.norm(raw);
    if (t.isEmpty) return l10n.djStFallback;
    final asks = t.contains('comment') ||
        t.contains('how') ||
        t.contains('quoi') ||
        t.contains('?');

    if (_hit(t, _howAreYou) && (asks || t.length <= 14)) {
      return l10n.djStHowAreYou;
    }
    if (_hit(t, _lowDay)) return l10n.djStLowDay;
    if (_hit(t, _goodDay)) return l10n.djStGoodDay;
    if (_hit(t, _whoIAm)) return l10n.djStWho;
    if (_hit(t, _thanks)) return l10n.djStThanks;
    if (_hit(t, _bye)) return l10n.djStBye;
    if (_hit(t, _askMusic)) return l10n.djStAskMusic;
    if (_hit(t, _greeting)) return l10n.djStGreeting;
    return l10n.djStFallback;
  }

  /// Les mots courts exigent des espaces autour (« hi » ne doit pas capturer
  /// « this ») ; les tournures longues se contentent d'une sous-chaîne.
  static bool _hit(String t, List<String> needles) {
    final padded = ' $t ';
    for (final n in needles) {
      if (n.length <= 3) {
        if (padded.contains(' $n ')) return true;
      } else if (t.contains(n)) {
        return true;
      }
    }
    return false;
  }

  static const List<String> _howAreYou = [
    'ca va', 'cava', 'cv', 'tu vas bien', 'vous allez bien',
    'quoi de neuf', 'koi neuf', 'bien ou mal',
    'how are you', 'how r u', 'how you doing', 'how is it going',
    'hows it going', 'how do you do', 'how are things', 'you okay',
  ];

  static const List<String> _greeting = [
    'bonjour', 'bonsoir', 'salut', 'coucou', 'hello', 'hi', 'hey', 'yo',
    'hola', 'ciao', 'good morning', 'good afternoon', 'good evening',
  ];

  static const List<String> _thanks = [
    'merci', 'grace a toi', 'nickel merci', 'thanks', 'thank you', 'ty',
    'appreciate it', 'perfect merci',
  ];

  static const List<String> _whoIAm = [
    'qui es tu', 'tu es qui', 'tes qui', 'c est qui', 'who are you',
    'what are you', 'c est quoi tunefy', 'what is tunefy', 'tu fais quoi',
  ];

  static const List<String> _bye = [
    'au revoir', 'a plus', 'a bientot', 'bonne route', 'bye', 'goodbye',
    'see you', 'ciao ciao',
  ];

  static const List<String> _askMusic = [
    'quoi ecouter', 'que ecouter', 'propose', 'suggestion', 'surprends moi',
    'met de la musique', 'lance quelque chose', 'tu ecoutes quoi',
    'suggest something', 'what should i listen', 'play something',
    'recommend', 'recommande',
  ];

  static const List<String> _lowDay = [
    'journee difficile', 'journee pourrie', 'grosse journee', 'ras le bol',
    'marre', 'pas le moral', 'j ai tenu', 'j ai craque', 'c dur', 'difficile',
    'je craque', 'noir', 'je suis a bout', 'a bout',
    'rough day', 'bad day', 'terrible day', 'long day', 'stressed',
    'overwhelmed', 'so tired', 'exhausted', 'i had a hard day',
  ];

  static const List<String> _goodDay = [
    'super journee', 'bonne journee', 'tres bien', 'je vais bien',
    'ca va bien', 'ca roule',
    'top', 'nickel', 'genial', 'super', 'je suis content', 'la peche',
    'good day', 'great day', 'amazing day', 'feeling good', 'i am good',
    'im good', 'pretty good', 'not bad',
  ];
}
