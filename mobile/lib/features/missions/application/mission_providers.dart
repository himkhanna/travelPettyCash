import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../data/mission_repository.dart';
import '../domain/mission.dart';

final Provider<MissionRepository> missionRepositoryProvider =
    Provider<MissionRepository>((Ref ref) {
  return MissionRepository(dio: ref.watch(dioProvider));
});

/// All missions the caller can see. Open to every authenticated role so the
/// trip picker can populate.
final FutureProvider<List<Mission>> missionsProvider =
    FutureProvider<List<Mission>>((Ref ref) async {
  return ref.read(missionRepositoryProvider).list();
});
