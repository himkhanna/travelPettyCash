import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_config.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../../core/money/money.dart';
import '../../auth/application/auth_providers.dart';
import '../../expenses/application/expenses_providers.dart';
import '../../expenses/domain/expense.dart';
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

/// All transfers on a trip (peer-to-peer money moves). Mirrors
/// [tripAllocationsProvider] for transfers so consumers can surface
/// pending-transfer pills/banners next to pending-allocation ones.
final FutureProviderFamily<List<Transfer>, String> tripTransfersProvider =
    FutureProvider.family<List<Transfer>, String>((
      Ref ref,
      String tripId,
    ) async {
      ref.watch(fakeRoleProvider);
      return ref.read(transferRepositoryProvider).forTrip(tripId);
    });

/// Leader's remaining-to-allocate budget per source. Computed via the pure
/// [computeLeaderAvailableBySource] so both fake and api impls share
/// the calculation. Both modes now fold in the leader's real expense list
/// so the displayed available budget reflects what the leader has actually
/// spent — no more inflated number from un-deducted spending.
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
        BackendMode.api => (await ref.watch(_leaderApiExpensesProvider(tripId).future))
            .map((Expense e) => (sourceId: e.sourceId, amount: e.amount))
            .toList(growable: false),
      };

      return computeLeaderAvailableBySource(
        allocations: allocs,
        leaderId: trip.leaderId,
        currency: trip.currency,
        leaderExpenses: leaderExpenses,
      );
    });

/// Internal helper: in API mode, fetch the leader's expense list on this
/// trip. Filtered server-side by userId=leaderId.
final FutureProviderFamily<List<Expense>, String> _leaderApiExpensesProvider =
    FutureProvider.family<List<Expense>, String>((
      Ref ref,
      String tripId,
    ) async {
      final Trip trip = await ref.watch(tripDetailProvider(tripId).future);
      return ref.read(expenseRepositoryProvider).list(
            tripId: tripId,
            userId: trip.leaderId,
          );
    });
