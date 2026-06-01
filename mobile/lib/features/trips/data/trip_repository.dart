import '../../../core/money/money.dart';
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
    required String countryName,
    required String currency,
    required String leaderId,
    required List<String> memberIds,
    required Money totalBudget,
    String? missionId,
  });

  /// Admin only.
  Future<Trip> closeTrip(String tripId);

  /// Admin only — partial update. Any null field is left unchanged. The
  /// `memberIds` list is the full replacement set, not a delta.
  Future<Trip> updateTrip({
    required String tripId,
    String? name,
    String? leaderId,
    List<String>? memberIds,
  });

  /// Admin only. Backend rejects with 409 `trips/has-expenses` if any
  /// expense has been logged against the trip — closed trips preserve the
  /// record, only freshly-created (no-activity) trips can be deleted.
  Future<void> deleteTrip(String tripId);
}
