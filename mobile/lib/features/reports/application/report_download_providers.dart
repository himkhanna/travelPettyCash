import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../data/report_download_repository.dart';

/// API-backed report download repository. Always uses the real backend
/// (CLAUDE.md §10 — server-rendered reports are not faked).
final Provider<ReportDownloadRepository> reportDownloadRepositoryProvider =
    Provider<ReportDownloadRepository>((Ref ref) {
  return ReportDownloadRepository(dio: ref.watch(dioProvider));
});
