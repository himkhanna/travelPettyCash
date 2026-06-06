import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_config.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../auth/application/auth_providers.dart';
import '../data/api_insights_repository.dart';
import '../data/fake_insights_repository.dart';
import '../data/insights_repository.dart';
import '../domain/insight.dart';

final Provider<InsightsRepository> insightsRepositoryProvider =
    Provider<InsightsRepository>((Ref ref) {
  final BackendMode mode = ref.watch(backendModeProvider);
  switch (mode) {
    case BackendMode.fake:
      return FakeInsightsRepository(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      );
    case BackendMode.api:
      return ApiInsightsRepository(dio: ref.watch(dioProvider));
  }
});

/// Smart Insights for one trip. Re-fetches when the demo role changes so the
/// card stays in step with the rest of the dashboard.
final FutureProviderFamily<TripInsights, String> tripInsightsProvider =
    FutureProvider.family<TripInsights, String>((Ref ref, String tripId) async {
  ref.watch(fakeRoleProvider);
  return ref.read(insightsRepositoryProvider).forTrip(tripId);
});
