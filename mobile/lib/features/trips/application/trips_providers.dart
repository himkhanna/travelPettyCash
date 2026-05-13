import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../auth/application/auth_providers.dart';
import '../data/fake_trip_repository.dart';
import '../data/trip_repository.dart';
import '../domain/trip.dart';

final Provider<TripRepository> tripRepositoryProvider = Provider<TripRepository>(
  (Ref ref) => FakeTripRepository(
    ref.watch(demoStoreProvider),
    ref.watch(fakeConfigProvider),
    currentUserId: () =>
        ref.read(currentUserProvider).valueOrNull?.id ?? '',
  ),
);

final FutureProvider<List<Trip>> activeTripsProvider = FutureProvider<List<Trip>>(
  (Ref ref) {
    // Refetch when role changes — different roles see different trips.
    ref.watch(fakeRoleProvider);
    return ref.read(tripRepositoryProvider).activeTrips();
  },
);

final FutureProviderFamily<Trip, String> tripDetailProvider =
    FutureProvider.family<Trip, String>(
  (Ref ref, String id) => ref.read(tripRepositoryProvider).tripById(id),
);

final FutureProviderFamily<TripBalances, ({String tripId, BalanceScope scope})>
    tripBalancesProvider = FutureProvider.family<
        TripBalances, ({String tripId, BalanceScope scope})>(
  (Ref ref, ({String tripId, BalanceScope scope}) args) {
    ref.watch(fakeRoleProvider);
    // Rebuild when sync queue drains so balances catch up with newly
    // accepted expenses.
    ref.watch(syncStateProvider);
    return ref.read(tripRepositoryProvider).balances(args.tripId, args.scope);
  },
);
