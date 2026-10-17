import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/services/supabase_store.dart';

final authServiceProvider = ChangeNotifierProvider<AuthService>((ref) {
  return AuthService(ref.watch(storageServiceProvider));
});

class AuthService extends ChangeNotifier {
  final StorageService _storage;
  static const String _baseUrl = 'https://tunefy-api.onrender.com/api/auth';
  // Google OAuth web client, configured in the Supabase Google provider. The
  // idToken audience MUST be this client so Supabase accepts it
  // (grant_type=id_token). The same client also authorizes this Android app
  // (package + SHA-1) in Google Console.
  static const String _googleWebClientId =
      '88850270860-0ce88nto9te6p359m016t7kb269i04ok.apps.googleusercontent.com';

  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    // This app ships NO google-services.json, so the client is passed
    // explicitly on every platform. The SAME web client also authorizes this
    // Android app (package + SHA-1) in Google Console. serverClientId makes the
    // returned idToken carry this client as its audience — exactly what the
    // Supabase Google provider validates (grant_type=id_token).
    clientId: _googleWebClientId,
    serverClientId: _googleWebClientId,
    scopes: ['email', 'profile'],
  );

  AuthService(this._storage);

  String? get token => _storage.authToken;
  bool get isAuthenticated => token != null;

  /// Google OAuth access token (for YouTube Music API)
  String? _googleAccessToken;
  String? get googleAccessToken => _googleAccessToken;

  /// Google OAuth refresh token (for YouTube Music token refresh)
  String? _googleRefreshToken;
  String? get googleRefreshToken => _googleRefreshToken;

  Future<void> signup(String username, String email, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final token = data['token'];
      final user = data['user'];

      await _storage.setAuthToken(token);
      await _storage.setUserInfo(
        user['username'],
        user['email'],
        avatarUrl: user['avatar'],
      );
      notifyListeners();
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Signup failed');
    }
  }

  Future<void> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final token = data['token'];
      final user = data['user'];

      await _storage.setAuthToken(token);
      await _storage.setUserInfo(
        user['username'],
        user['email'],
        avatarUrl: user['avatar'],
      );
      notifyListeners();
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Login failed');
    }
  }

  Future<void> loginWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return; 
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      // Capture access_token for YouTube Music API
      _googleAccessToken = googleAuth.accessToken;
      debugPrint('Google Sign-In: accessToken=${_googleAccessToken != null ? "obtained" : "null"}');

      if (idToken == null) {
        throw Exception('Failed to get ID token from Google.');
      }

      // Exchange the Google ID token for a Supabase session via GoTrue
      // (grant_type=id_token). This replaces the old Render /api/auth/google
      // call, whose backend never implemented that route (Google login was
      // broken). Supabase validates the idToken's audience against the web
      // client configured in its Google provider.
      final resp = await http.post(
        Uri.parse('${SupabaseStore.url}/auth/v1/token?grant_type=id_token'),
        headers: {
          'apikey': SupabaseStore.anonKey,
          'Authorization': 'Bearer ${SupabaseStore.anonKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'id_token': idToken,
          'provider': 'google',
          if (googleAuth.accessToken != null)
            'access_token': googleAuth.accessToken,
        }),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final token = data['access_token']?.toString();
        final user = data['user'];
        if (token == null) {
          throw Exception('Supabase Google sign-in: missing access_token');
        }
        final meta = user?['user_metadata'];
        await _storage.setAuthToken(token);
        await _storage.setUserInfo(
          meta?['full_name']?.toString() ??
              user?['email']?.toString() ??
              'User',
          user?['email']?.toString() ?? '',
          avatarUrl: meta?['avatar_url']?.toString(),
        );
        notifyListeners();
      } else {
        throw Exception('Supabase Google sign-in ${resp.statusCode}: ${resp.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('Google Sign-In Exception: $e');
      debugPrint('Stack trace: $stackTrace');
      throw Exception('Google Sign-In Error: $e');
    }
  }

  Future<void> logout() async {
    await _googleSignIn.signOut();
    await _storage.clearUserSession();
    notifyListeners();
  }

  Future<String?> refreshToken() async {
    final currentToken = _storage.authToken;
    if (currentToken == null) return null;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/refresh'),
        headers: {
          'Authorization': 'Bearer $currentToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newToken = data['token'];
        final user = data['user'];

        await _storage.setAuthToken(newToken);
        if (user != null) {
          await _storage.setUserInfo(
            user['username'],
            user['email'],
            avatarUrl: user['avatar'],
          );
        }
        notifyListeners();
        return newToken;
      } else {
        debugPrint('Token refresh failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error refreshing token: $e');
      return null;
    }
  }

  Future<bool> verifyToken() async {
    final currentToken = _storage.authToken;
    if (currentToken == null) return false;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/verify'),
        headers: {'Authorization': 'Bearer $currentToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['valid'] == true;
      } else {
        return false;
      }
    } catch (e) {
      debugPrint('Error verifying token: $e');
      return false;
    }
  }
}
