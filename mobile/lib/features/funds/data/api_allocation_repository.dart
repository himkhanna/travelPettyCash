import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../../../core/money/money.dart';
import '../domain/funding.dart';
import 'funds_repository.dart';

class ApiAllocationRepository implements AllocationRepository {
  ApiAllocationRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<List<Allocation>> forTrip(String tripId, {String? memberId}) async {
    final Map<String, dynamic> query = <String, dynamic>{};
    if (memberId != null) query['memberId'] = memberId;
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/trips/$tripId/allocations',
        queryParameters: query,
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _allocFromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<List<Allocation>> createMany({
    required String tripId,
    required List<AllocationDraftRow> rows,
    required String idempotencyKey,
  }) async {
    final List<Map<String, dynamic>> body = rows
        .map((AllocationDraftRow r) => <String, dynamic>{
              'toUserId': r.toUserId,
              'sourceId': r.sourceId,
              'amount': <String, dynamic>{
                'amount': r.amount.amountMinor,
                'currency': r.amount.currencyCode,
              },
            })
        .toList(growable: false);
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/trips/$tripId/allocations',
        data: <String, dynamic>{'rows': body},
        options: Options(headers: <String, dynamic>{
          'Idempotency-Key': idempotencyKey,
        }),
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _allocFromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<Allocation> respond({
    required String allocationId,
    required AllocationStatus response,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/allocations/$allocationId/respond',
        data: <String, dynamic>{'response': _statusToApi(response)},
      );
      return _allocFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  Allocation _allocFromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> amount = j['amount'] as Map<String, dynamic>;
    return Allocation(
      id: j['id'] as String,
      tripId: j['tripId'] as String,
      fromUserId: j['fromUserId'] as String?,
      toUserId: j['toUserId'] as String,
      sourceId: j['sourceId'] as String,
      amount: Money(amount['amount'] as int, amount['currency'] as String),
      status: _statusFromApi(j['status'] as String),
      note: j['note'] as String?,
      createdAt: DateTime.parse(j['createdAt'] as String),
      respondedAt: j['respondedAt'] == null
          ? null
          : DateTime.parse(j['respondedAt'] as String),
    );
  }

  AllocationStatus _statusFromApi(String s) {
    switch (s) {
      case 'PENDING':
        return AllocationStatus.pending;
      case 'ACCEPTED':
        return AllocationStatus.accepted;
      case 'DECLINED':
        return AllocationStatus.declined;
      default:
        throw ArgumentError('Unknown allocation status: $s');
    }
  }

  String _statusToApi(AllocationStatus s) {
    switch (s) {
      case AllocationStatus.pending:
        return 'PENDING';
      case AllocationStatus.accepted:
        return 'ACCEPTED';
      case AllocationStatus.declined:
        return 'DECLINED';
    }
  }
}
