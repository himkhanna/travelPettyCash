import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';

/// Shape of the public `GET /api/v1/auth/config` response — fetched
/// once at app boot so the LoginScreen can decide whether to render
/// the "Sign in with Dubai Gov" button and / or the local-login
/// username + password form.
class AuthConfig {
  const AuthConfig({
    required this.localLoginEnabled,
    required this.dubaiGovSsoEnabled,
    required this.uaePassSsoEnabled,
  });

  final bool localLoginEnabled;
  final bool dubaiGovSsoEnabled;
  final bool uaePassSsoEnabled;

  factory AuthConfig.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic>? local =
        j['localLogin'] as Map<String, dynamic>?;
    final Map<String, dynamic>? sso = j['sso'] as Map<String, dynamic>?;
    final Map<String, dynamic>? dgov =
        sso == null ? null : sso['dubaigov'] as Map<String, dynamic>?;
    final Map<String, dynamic>? uaepass =
        sso == null ? null : sso['uaepass'] as Map<String, dynamic>?;
    return AuthConfig(
      localLoginEnabled: (local?['enabled'] as bool?) ?? true,
      dubaiGovSsoEnabled: (dgov?['enabled'] as bool?) ?? false,
      uaePassSsoEnabled: (uaepass?['enabled'] as bool?) ?? false,
    );
  }

  /// Fallback when the probe fails — assume local login is on and
  /// SSO is off so we never lock the user out of the login screen.
  static const AuthConfig fallback = AuthConfig(
    localLoginEnabled: true,
    dubaiGovSsoEnabled: false,
    uaePassSsoEnabled: false,
  );
}

class AuthConfigRepository {
  AuthConfigRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<AuthConfig> fetch() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('/api/v1/auth/config');
      return AuthConfig.fromJson(resp.data as Map<String, dynamic>);
    } catch (_) {
      // Older backend / offline / network failure → fall back so the
      // login screen still renders. The user can still hit the local
      // login form and authenticate normally.
      return AuthConfig.fallback;
    }
  }
}

final Provider<AuthConfigRepository> authConfigRepositoryProvider =
    Provider<AuthConfigRepository>((Ref ref) {
  return AuthConfigRepository(dio: ref.watch(dioProvider));
});

/// Loaded once at app boot. The login screens watch this.
final FutureProvider<AuthConfig> authConfigProvider =
    FutureProvider<AuthConfig>((Ref ref) {
  return ref.read(authConfigRepositoryProvider).fetch();
});
