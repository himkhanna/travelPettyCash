import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fake/fake_config.dart';
import '../data/fake_report_repository.dart';
import '../data/report_repository.dart';

final Provider<ReportRepository> reportRepositoryProvider =
    Provider<ReportRepository>(
  (Ref ref) => FakeReportRepository(ref.watch(fakeConfigProvider)),
);
