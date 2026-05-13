import '../domain/user.dart';

abstract class AuthRepository {
  Future<AuthSession> login({required String username, required String password});
  Future<AuthSession> loginAsRole(UserRole role);
  Future<void> logout();
  Future<User?> currentUser();
}

class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  final User user;
  final String accessToken;
  final String refreshToken;
}
