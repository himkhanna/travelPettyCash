import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent home for the access + refresh tokens issued by `/auth/login`
/// and `/auth/refresh`. Implementations:
///   * [SecureTokenStore] — flutter_secure_storage (Keychain / Keystore / web
///     IndexedDB+webcrypto). Default outside tests.
///   * [InMemoryTokenStore] — process-local; used in tests and as a safe
///     fallback on platforms where secure_storage init fails.
abstract class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

@immutable
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  AuthTokens copyWith({String? accessToken, String? refreshToken}) =>
      AuthTokens(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
      );
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const String _kAccess = 'pdd.auth.access';
  static const String _kRefresh = 'pdd.auth.refresh';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthTokens?> read() async {
    final String? access = await _storage.read(key: _kAccess);
    final String? refresh = await _storage.read(key: _kRefresh);
    if (access == null || refresh == null) return null;
    return AuthTokens(accessToken: access, refreshToken: refresh);
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    await _storage.write(key: _kAccess, value: tokens.accessToken);
    await _storage.write(key: _kRefresh, value: tokens.refreshToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }
}

class InMemoryTokenStore implements TokenStore {
  AuthTokens? _tokens;

  @override
  Future<AuthTokens?> read() async => _tokens;

  @override
  Future<void> write(AuthTokens tokens) async {
    _tokens = tokens;
  }

  @override
  Future<void> clear() async {
    _tokens = null;
  }
}

/// shared_preferences-backed store. Used on Flutter Web because
/// flutter_secure_storage_web depends on `window.crypto.subtle`, which
/// browsers only expose on secure contexts (HTTPS or localhost). When
/// the page is served over a plain-HTTP LAN URL (e.g. an iPhone hitting
/// `http://192.168.1.46:5173`), subtle is undefined and SecureTokenStore
/// crashes the bundle at init. shared_preferences uses localStorage on
/// web with no such restriction.
class WebTokenStore implements TokenStore {
  static const String _kAccess = 'pdd.auth.access';
  static const String _kRefresh = 'pdd.auth.refresh';

  @override
  Future<AuthTokens?> read() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? access = prefs.getString(_kAccess);
    final String? refresh = prefs.getString(_kRefresh);
    if (access == null || refresh == null) return null;
    return AuthTokens(accessToken: access, refreshToken: refresh);
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, tokens.accessToken);
    await prefs.setString(_kRefresh, tokens.refreshToken);
  }

  @override
  Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
  }
}

final Provider<TokenStore> tokenStoreProvider = Provider<TokenStore>(
  (Ref ref) => kIsWeb ? WebTokenStore() : SecureTokenStore(),
);
