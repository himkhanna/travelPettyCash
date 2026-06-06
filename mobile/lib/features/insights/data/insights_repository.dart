import '../domain/insight.dart';

/// Fetches deterministic Smart Insights for a trip. Implemented by an API
/// repo (backend engine) and a fake repo (demo/offline mode).
abstract class InsightsRepository {
  Future<TripInsights> forTrip(String tripId);
}
