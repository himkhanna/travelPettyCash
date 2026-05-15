import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_config.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../data/api_auth_repository.dart';
import '../data/auth_repository.dart';
import '../data/fake_auth_repository.dart';
import '../domain/user.dart';

/// Switches between FakeAuthRepository and ApiAuthRepository based on the
/// currently-selected [BackendMode]. Flipping the toggle in DevMenu causes
/// every downstream consumer to rebuild against the new impl.
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((Ref ref) {
  final BackendMode mode = ref.watch(backendModeProvider);
  switch (mode) {
    case BackendMode.fake:
      return FakeAuthRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      );
    case BackendMode.api:
      return ApiAuthRepository(
        dio: ref.watch(dioProvider),
        tokens: ref.watch(tokenStoreProvider),
      );
  }
});

/// Hydrates from FakeConfig.role (demo mode) or `/api/v1/me` (api mode).
final FutureProvider<User?> currentUserProvider = FutureProvider<User?>((
  Ref ref,
) async {
  // Re-evaluate whenever the role switches in the dev menu OR the backend
  // mode flips between fake and api.
  ref.watch(fakeRoleProvider);
  ref.watch(backendModeProvider);
  final AuthRepository repo = ref.read(authRepositoryProvider);
  return repo.currentUser();
});

/// Convenience accessor — throws if unauthenticated. Use only inside trees
/// that are only reachable after role selection (i.e. /m/*).
final Provider<User> requireUserProvider = Provider<User>((Ref ref) {
  final AsyncValue<User?> u = ref.watch(currentUserProvider);
  return u.maybeWhen(
    data: (User? v) {
      if (v == null) {
        throw StateError('requireUser called before role is set');
      }
      return v;
    },
    orElse: () => throw StateError('User not loaded yet'),
  );
});

/// Watches the FakeConfig.role channel so currentUserProvider can rebuild
/// when the role switcher fires.
final Provider<FakeRole> fakeRoleProvider = Provider<FakeRole>((Ref ref) {
  final FakeConfig cfg = ref.watch(fakeConfigProvider);
  // FakeConfig is a ChangeNotifier; bind it to Riverpod's rebuild loop.
  ref.listen<FakeConfig>(fakeConfigProvider, (_, FakeConfig c) {});
  cfg.addListener(ref.invalidateSelf);
  ref.onDispose(() => cfg.removeListener(ref.invalidateSelf));
  return cfg.role;
});
