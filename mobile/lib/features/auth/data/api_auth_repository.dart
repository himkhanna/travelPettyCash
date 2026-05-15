import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../../../core/auth/token_store.dart';
import '../domain/user.dart';
import 'auth_repository.dart';

/// Real backend implementation of [AuthRepository] — talks to the Spring Boot
/// service at `/api/v1/auth/*` and `/api/v1/me`. Mirrors the wire shape
/// defined in `backend/.../auth/dto/`.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({required Dio dio, required TokenStore tokens})
      : _dio = dio,
        _tokens = tokens;

  final Dio _dio;
  final TokenStore _tokens;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio.post<dynamic>(
        '/api/v1/auth/login',
        data: <String, String>{'username': username, 'password': password},
      );
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
    return _sessionFromBody(resp);
  }

  @override
  Future<AuthSession> loginAsRole(UserRole role) {
    // The real backend has no "log in as any user of role X" affordance —
    // that's a demo-only convenience on the fake repo. Reject early so a
    // misrouted role-pick from the landing page surfaces clearly.
    throw UnsupportedError(
      'loginAsRole is a demo-only path; pick a username/password instead.',
    );
  }

  @override
  Future<void> logout() async {
    await _tokens.clear();
  }

  @override
  Future<User?> currentUser() async {
    final AuthTokens? t = await _tokens.read();
    if (t == null) return null;
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('/api/v1/me');
      if (resp.statusCode != 200) return null;
      return _userFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      // 401 here means the refresh interceptor already gave up — treat as
      // logged out so the UI bounces to /login rather than spinning.
      if (e.response?.statusCode == 401) {
        await _tokens.clear();
        return null;
      }
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  Future<AuthSession> _sessionFromBody(Response<dynamic> resp) async {
    final Map<String, dynamic> body = resp.data as Map<String, dynamic>;
    final Map<String, dynamic> t = body['tokens'] as Map<String, dynamic>;
    final String access = t['accessToken'] as String;
    final String refresh = t['refreshToken'] as String;
    await _tokens.write(
      AuthTokens(accessToken: access, refreshToken: refresh),
    );
    final User user = _userFromJson(body['user'] as Map<String, dynamic>);
    return AuthSession(
      user: user,
      accessToken: access,
      refreshToken: refresh,
    );
  }

  User _userFromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['displayName'] as String,
        displayNameAr: j['displayNameAr'] as String,
        email: j['email'] as String,
        role: UserRole.fromApiCode(j['role'] as String),
        isActive: true,
      );
}
