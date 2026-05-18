import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../data/audit_repository.dart';
import '../domain/audit_entry.dart';

final Provider<AuditRepository> auditRepositoryProvider =
    Provider<AuditRepository>((Ref ref) {
  return AuditRepository(dio: ref.watch(dioProvider));
});

/// Live audit feed (no filters). Admin/Super-only on the server, so non-
/// admin callers will see a 403 in the AsyncError.
final FutureProvider<List<AuditEntry>> auditFeedProvider =
    FutureProvider<List<AuditEntry>>((Ref ref) async {
  return ref.read(auditRepositoryProvider).list();
});
