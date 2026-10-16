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
}
