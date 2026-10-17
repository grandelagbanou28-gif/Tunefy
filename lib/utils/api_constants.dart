class ApiConstants {
  /// Extended worker used for all search, related, feeds, and albums
  static const String extendedWorkerBaseUrl = 'https://backend-grandelagbanou28-gifs-projects.vercel.app';

  /// Main application data and user backend
  /// Backend "pro" (FastAPI + Supabase) déployé sur Render (free, sans carte).
  static const String mainApiBaseUrl = 'https://tunefy-api.onrender.com/api';

  /// Jamendo API client id (free, keyless streaming of Creative-Commons
  /// music). Used as the fast/reliable primary source, YouTube as fallback.
  static const String jamendoClientId = '25428729';

  /// Backend proxy de streaming (yt-dlp côté serveur) utilisé par le build
  /// WEB uniquement : le navigateur ne peut pas extraire un flux googlevideo
  /// lui-même, ce backend résout l'audio et le rend streamable (CORS + Range).
  /// Surchargeable au build : --dart-define=WEB_STREAM_API_BASE=https://...
  static const String webStreamApiBaseUrl = String.fromEnvironment(
    'WEB_STREAM_API_BASE',
    defaultValue: 'https://tunefy-ytdlp.vercel.app',
  );

  /// Cloud stream relay (server/main.py on Render). Resolves AND relays the
  /// audio bytes so the phone's requests share the relay's public IP — this
  /// avoids the HTTP 403 a bare googlevideo URL returns when the phone's IP
  /// differs from the one that resolved it. Empty until the Render service is
  /// deployed; set at build: --dart-define=RELAY_BASE_URL=https://....
  static const String relayBaseUrl = String.fromEnvironment('RELAY_BASE_URL');

  /// Shared secret (RELAY_KEY env on Render). Sent as `key` on /stream so the
  /// public relay URL cannot be used as a free proxy to drain the free tier.
  /// This is a low-sensitivity gate (it ships in the APK by design); it is NOT
  /// the Google client secret, which stays server-side in Supabase only.
  static const String relayKey = String.fromEnvironment(
    'RELAY_KEY',
    defaultValue: 'ef18836a78d502fd085b90c1ae497419919a19ce5234bc13',
  );
}
