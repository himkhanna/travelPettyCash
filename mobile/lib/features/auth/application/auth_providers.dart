import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../data/auth_repository.dart';
import '../data/fake_auth_repository.dart';
import '../domain/user.dart';

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (Ref ref) => FakeAuthRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      ),
    );

/// Hydrates from FakeConfig.role so the landing-page choice becomes the
/// current user without an explicit login call.
final FutureProvider<User?> currentUserProvider = FutureProvider<User?>((
  Ref ref,
) async {
  // Re-evaluate whenever the role switches in the dev menu.
  ref.watch(fakeRoleProvider);
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
