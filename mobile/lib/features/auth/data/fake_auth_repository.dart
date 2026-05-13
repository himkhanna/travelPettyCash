import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../domain/user.dart';
import 'auth_repository.dart';

/// Maps the landing-page role choice (FakeRole) to a seed user and "logs in"
/// as that user. No password check — this is a demo, see project memory
/// [[project-build-order-ui-first]].
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this._store, this._cfg);

  final DemoStore _store;
  final FakeConfig _cfg;

  User? _current;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    final User user = _store.users.firstWhere(
      (User u) => u.username == username,
      orElse: () => throw StateError('Unknown demo user: $username'),
    );
    _current = user;
    _cfg.setRole(_roleFor(user));
    return _session(user);
  }

  @override
  Future<AuthSession> loginAsRole(UserRole role) async {
    await _store.ensureLoaded();
    final User user = _store.users.firstWhere(
      (User u) => u.role == role,
      orElse: () => throw StateError('No seed user for role: $role'),
    );
    _current = user;
    return _session(user);
  }

  @override
  Future<void> logout() async {
    _current = null;
    _cfg.setRole(FakeRole.unset);
  }

  @override
  Future<User?> currentUser() async {
    if (_current != null) return _current;
    await _store.ensureLoaded();
    // If the role was set via the landing page, hydrate from there.
    final UserRole? r = _domainRoleFor(_cfg.role);
    if (r == null) return null;
    _current = _store.users.firstWhere(
      (User u) => u.role == r,
      orElse: () => throw StateError('No seed user for role $r'),
    );
    return _current;
  }

  AuthSession _session(User user) => AuthSession(
    user: user,
    accessToken: 'demo-access-${user.id}',
    refreshToken: 'demo-refresh-${user.id}',
  );

  FakeRole _roleFor(User u) {
    switch (u.role) {
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

  UserRole? _domainRoleFor(FakeRole r) {
    switch (r) {
      case FakeRole.member:
        return UserRole.member;
      case FakeRole.leader:
        return UserRole.leader;
      case FakeRole.admin:
        return UserRole.admin;
      case FakeRole.superAdmin:
        return UserRole.superAdmin;
      case FakeRole.unset:
        return null;
    }
  }
}
