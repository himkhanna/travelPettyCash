import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../../core/money/money.dart';
import '../../auth/application/auth_providers.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../data/fake_allocation_repository.dart';
import '../data/fake_source_repository.dart';
import '../data/fake_transfer_repository.dart';
import '../data/funds_repository.dart';
import '../domain/funding.dart';

final Provider<SourceRepository> sourceRepositoryProvider =
    Provider<SourceRepository>(
      (Ref ref) => FakeSourceRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      ),
    );

final Provider<TransferRepository> transferRepositoryProvider =
    Provider<TransferRepository>(
      (Ref ref) => FakeTransferRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      ),
    );

final FutureProvider<List<Source>> sourcesProvider = FutureProvider<List<Source>>(
  (Ref ref) => ref.read(sourceRepositoryProvider).all(),
);

final Provider<AllocationRepository> allocationRepositoryProvider =
    Provider<AllocationRepository>(
      (Ref ref) => FakeAllocationRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      ),
    );

final FutureProviderFamily<List<Allocation>, String> tripAllocationsProvider =
    FutureProvider.family<List<Allocation>, String>((
      Ref ref,
      String tripId,
    ) async {
      ref.watch(fakeRoleProvider);
      return ref.read(allocationRepositoryProvider).forTrip(tripId);
    });

/// Leader's remaining-to-allocate budget per source. Subtracts pending +
/// accepted allocations so the Leader can't double-spend. Recomputed via
/// tripAllocationsProvider dependency.
final FutureProviderFamily<Map<String, Money>, String>
leaderAvailableBySourceProvider =
    FutureProvider.family<Map<String, Money>, String>((
      Ref ref,
      String tripId,
    ) async {
      ref.watch(fakeRoleProvider);
      ref.watch(tripAllocationsProvider(tripId));
      final Trip trip = await ref.watch(tripDetailProvider(tripId).future);
      final FakeAllocationRepository repo =
          ref.read(allocationRepositoryProvider) as FakeAllocationRepository;
      return repo.leaderAvailableBySource(
        tripId: tripId,
        leaderId: trip.leaderId,
        currency: trip.currency,
      );
    });
