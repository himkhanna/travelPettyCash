import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_config.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../../core/money/money.dart';
import '../../auth/application/auth_providers.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../data/api_allocation_repository.dart';
import '../data/api_source_repository.dart';
import '../data/api_transfer_repository.dart';
import '../data/fake_allocation_repository.dart';
import '../data/fake_source_repository.dart';
import '../data/fake_transfer_repository.dart';
import '../data/funds_repository.dart';
import '../domain/funding.dart';
import '../domain/funds_calculations.dart';

final Provider<SourceRepository> sourceRepositoryProvider =
    Provider<SourceRepository>((Ref ref) {
  final BackendMode mode = ref.watch(backendModeProvider);
  switch (mode) {
    case BackendMode.fake:
      return FakeSourceRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      );
    case BackendMode.api:
      return ApiSourceRepository(dio: ref.watch(dioProvider));
  }
});

final Provider<TransferRepository> transferRepositoryProvider =
    Provider<TransferRepository>((Ref ref) {
  final BackendMode mode = ref.watch(backendModeProvider);
  switch (mode) {
    case BackendMode.fake:
      return FakeTransferRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      );
    case BackendMode.api:
      return ApiTransferRepository(dio: ref.watch(dioProvider));
  }
});

final FutureProvider<List<Source>> sourcesProvider = FutureProvider<List<Source>>(
  (Ref ref) => ref.read(sourceRepositoryProvider).all(),
);

final Provider<AllocationRepository> allocationRepositoryProvider =
    Provider<AllocationRepository>((Ref ref) {
  final BackendMode mode = ref.watch(backendModeProvider);
  switch (mode) {
    case BackendMode.fake:
      return FakeAllocationRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      );
    case BackendMode.api:
      return ApiAllocationRepository(dio: ref.watch(dioProvider));
  }
});

final FutureProviderFamily<List<Allocation>, String> tripAllocationsProvider =
    FutureProvider.family<List<Allocation>, String>((
      Ref ref,
      String tripId,
    ) async {
      ref.watch(fakeRoleProvider);
      return ref.read(allocationRepositoryProvider).forTrip(tripId);
    });

/// Leader's remaining-to-allocate budget per source. Computed via the pure
/// [computeLeaderAvailableBySource] so both fake and api impls share
/// the calculation. In api mode the leader's expense list is empty until
/// the expense backend slice ships — the value will look inflated by the
/// leader's own pending expenses, which is a documented limitation.
final FutureProviderFamily<Map<String, Money>, String>
leaderAvailableBySourceProvider =
    FutureProvider.family<Map<String, Money>, String>((
      Ref ref,
      String tripId,
    ) async {
      ref.watch(fakeRoleProvider);
      final BackendMode mode = ref.watch(backendModeProvider);
      final Trip trip = await ref.watch(tripDetailProvider(tripId).future);
      final List<Allocation> allocs =
          await ref.watch(tripAllocationsProvider(tripId).future);

      // In fake mode, fold in the leader's local expenses so the
      // available-budget display matches the data the user sees on the
      // expenses screen. In api mode the expense backend isn't live yet
      // so we pass an empty list.
      final List<({String sourceId, Money amount})> leaderExpenses =
          switch (mode) {
        BackendMode.fake => ref
            .read(demoStoreProvider)
            .expenses
            .where((dynamic e) =>
                e.tripId == tripId &&
                e.userId == trip.leaderId &&
                e.deletedAt == null)
            .map<({String sourceId, Money amount})>((dynamic e) => (
                  sourceId: e.sourceId as String,
                  amount: e.amount as Money,
                ))
            .toList(growable: false),
        BackendMode.api => const <({String sourceId, Money amount})>[],
      };

      return computeLeaderAvailableBySource(
        allocations: allocs,
        leaderId: trip.leaderId,
        currency: trip.currency,
        leaderExpenses: leaderExpenses,
      );
    });
