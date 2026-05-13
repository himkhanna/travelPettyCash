import '../domain/trip.dart';

abstract class TripRepository {
  Future<List<Trip>> activeTrips();
  Future<List<Trip>> allTrips({TripStatus? status});
  Future<Trip> tripById(String id);
  Future<TripBalances> balances(String tripId, BalanceScope scope);

  /// Admin only.
  Future<Trip> createTrip({
    required String name,
    required String countryCode,
    required String currency,
    required String leaderId,
    required List<String> memberIds,
  });

  /// Admin only.
  Future<Trip> closeTrip(String tripId);
}
