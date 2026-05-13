import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../domain/user.dart';

/// Overridden in main.dart with the FakeAuthRepository (Milestone A) and later
/// with ApiAuthRepository (Phase 3 / backend integration).
final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>(
  (Ref ref) => throw UnimplementedError(
    'authRepositoryProvider must be overridden in main.dart',
  ),
);

/// Current authenticated user. Null when on the landing page.
final StateProvider<User?> currentUserProvider = StateProvider<User?>((Ref ref) => null);
