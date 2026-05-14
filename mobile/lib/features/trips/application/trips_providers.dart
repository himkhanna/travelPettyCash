import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../data/fake_trip_repository.dart';
import '../data/trip_repository.dart';
import '../domain/trip.dart';

final Provider<TripRepository> tripRepositoryProvider = Provider<TripRepository>(
  (Ref ref) => FakeTripRepository(
    ref.watch(demoStoreProvider),
    ref.watch(fakeConfigProvider),
    currentUserId: () => ref.read(currentUserProvider).valueOrNull?.id ?? '',
  ),
);

/// `await ref.watch(currentUserProvider.future)` does two things: it subscribes
/// to user changes (so this rebuilds when the landing-page role switcher fires)
/// AND it awaits the future so the repository's currentUserId() closure
/// returns the fresh value, not the stale one from the previous role.
final FutureProvider<List<Trip>> activeTripsProvider = FutureProvider<List<Trip>>(
  (Ref ref) async {
    final User? user = await ref.watch(currentUserProvider.future);
    if (user == null) return <Trip>[];
    return ref.read(tripRepositoryProvider).activeTrips();
  },
);

final FutureProviderFamily<Trip, String> tripDetailProvider =
    FutureProvider.family<Trip, String>(
      (Ref ref, String id) async {
        await ref.watch(currentUserProvider.future);
        return ref.read(tripRepositoryProvider).tripById(id);
      },
    );

final FutureProviderFamily<TripBalances, ({String tripId, BalanceScope scope})>
tripBalancesProvider =
    FutureProvider.family<TripBalances, ({String tripId, BalanceScope scope})>(
      (Ref ref, ({String tripId, BalanceScope scope}) args) async {
        final User? user = await ref.watch(currentUserProvider.future);
        if (user == null) {
          throw StateError('No current user — cannot compute balances');
        }
        ref.watch(syncStateProvider);
        return ref.read(tripRepositoryProvider).balances(args.tripId, args.scope);
      },
    );
