import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
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
