import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/trip_repository.dart';
import '../domain/trip.dart';

final Provider<TripRepository> tripRepositoryProvider = Provider<TripRepository>(
  (Ref ref) => throw UnimplementedError(
    'tripRepositoryProvider must be overridden in main.dart',
  ),
);

final FutureProvider<List<Trip>> activeTripsProvider = FutureProvider<List<Trip>>(
  (Ref ref) => ref.read(tripRepositoryProvider).activeTrips(),
);

final FutureProviderFamily<Trip, String> tripDetailProvider =
    FutureProvider.family<Trip, String>(
  (Ref ref, String id) => ref.read(tripRepositoryProvider).tripById(id),
);

final FutureProviderFamily<TripBalances, ({String tripId, BalanceScope scope})>
    tripBalancesProvider = FutureProvider.family<
        TripBalances, ({String tripId, BalanceScope scope})>(
  (Ref ref, ({String tripId, BalanceScope scope}) args) =>
      ref.read(tripRepositoryProvider).balances(args.tripId, args.scope),
);
