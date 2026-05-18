import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../../../core/money/money.dart';
import '../domain/audit_entry.dart';

/// Reads the unified audit feed from the backend. Admin/Super-only on the
/// server side — calls from non-admin tokens get a 403.
class AuditRepository {
  AuditRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<List<AuditEntry>> list({
    String? tripId,
    String? actorId,
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/audit',
        queryParameters: <String, dynamic>{
          if (tripId != null) 'tripId': tripId,
          if (actorId != null) 'actorId': actorId,
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': to.toUtc().toIso8601String(),
          'limit': limit,
        },
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  AuditEntry _fromJson(Map<String, dynamic> j) {
    Money? amount;
    final Map<String, dynamic>? amt = j['amount'] as Map<String, dynamic>?;
    if (amt != null) {
      amount = Money(amt['amount'] as int, amt['currency'] as String);
    }
    return AuditEntry(
      id: j['id'] as String,
      at: DateTime.parse(j['at'] as String),
      action: AuditAction.fromWire(j['action'] as String),
      actorId: j['actorId'] as String?,
      actorName: j['actorName'] as String? ?? '—',
      actorRole: j['actorRole'] as String? ?? '—',
      targetUserId: j['targetUserId'] as String?,
      targetUserName: j['targetUserName'] as String?,
      tripId: j['tripId'] as String?,
      tripName: j['tripName'] as String?,
      amount: amount,
      summary: j['summary'] as String? ?? '',
    );
  }
}
