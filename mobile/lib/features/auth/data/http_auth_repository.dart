import '../../../core/api/api_client.dart';
import '../../../core/fake/fake_config.dart';
import '../domain/user.dart';
import 'auth_repository.dart';

/// HTTP-backed auth: hits /api/v1/auth/login + /api/v1/me on the Spring
/// backend. There's no password yet — the request body just carries the
/// username, matching CLAUDE.md §16 (UAE Pass integration pending).
class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._api, this._cfg);

  final ApiClient _api;
  final FakeConfig _cfg;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final Map<String, dynamic> body = await _api.post<Map<String, dynamic>>(
      '/api/v1/auth/login',
      body: <String, dynamic>{'username': username},
    );
    final String token = body['accessToken'] as String;
    _cfg.setAuthToken(token);
    final User user = _parseUser(body['user'] as Map<String, dynamic>);
    _cfg.setRole(_fakeRoleFor(user.role));
    return AuthSession(
      user: user,
      accessToken: token,
      refreshToken: token, // no refresh-token endpoint yet
    );
  }

  @override
  Future<AuthSession> loginAsRole(UserRole role) async {
    final String username = switch (role) {
      UserRole.member => 'ahmed.maktoum',
      UserRole.leader => 'fatima.hashimi',
      UserRole.admin => 'khalid.suwaidi',
      UserRole.superAdmin => 'noura.falasi',
    };
    return login(username: username, password: '');
  }

  @override
  Future<void> logout() async {
    _cfg.setAuthToken(null);
    _cfg.setRole(FakeRole.unset);
  }

  @override
  Future<User?> currentUser() async {
    if (_cfg.authToken == null) return null;
    try {
      final Map<String, dynamic> json =
          await _api.get<Map<String, dynamic>>('/api/v1/me');
      return _parseUser(json);
    } catch (_) {
      return null;
    }
  }

  User _parseUser(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['displayName'] as String,
        displayNameAr: j['displayNameAr'] as String,
        email: j['email'] as String,
        role: UserRole.fromApiCode(j['role'] as String),
        isActive: (j['active'] as bool?) ?? true,
      );

  FakeRole _fakeRoleFor(UserRole r) {
    switch (r) {
      case UserRole.member:
        return FakeRole.member;
      case UserRole.leader:
        return FakeRole.leader;
      case UserRole.admin:
        return FakeRole.admin;
      case UserRole.superAdmin:
        return FakeRole.superAdmin;
    }
  }
}
