import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../../../core/money/money.dart';
import '../domain/funding.dart';
import 'funds_repository.dart';

class ApiTransferRepository implements TransferRepository {
  ApiTransferRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<List<Transfer>> forTrip(String tripId) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/trips/$tripId/transfers',
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _transferFromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<Transfer> create({
    required String clientUuid,
    required String tripId,
    required String fromUserId,
    required String toUserId,
    required String sourceId,
    required Money amount,
    String? note,
    required String idempotencyKey,
  }) async {
    // The clientUuid + idempotencyKey from the mobile layer collapse into one
    // header on the wire — the backend dedupes by (key, user, endpoint).
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/trips/$tripId/transfers',
        data: <String, dynamic>{
          'toUserId': toUserId,
          'sourceId': sourceId,
          'amount': <String, dynamic>{
            'amount': amount.amountMinor,
            'currency': amount.currencyCode,
          },
          if (note != null) 'note': note,
        },
        options: Options(headers: <String, dynamic>{
          'Idempotency-Key': idempotencyKey,
        }),
      );
      return _transferFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<Transfer> respond({
    required String transferId,
    required AllocationStatus response,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/transfers/$transferId/respond',
        data: <String, dynamic>{'response': _statusToApi(response)},
      );
      return _transferFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  Transfer _transferFromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> amount = j['amount'] as Map<String, dynamic>;
    return Transfer(
      id: j['id'] as String,
      tripId: j['tripId'] as String,
      fromUserId: j['fromUserId'] as String,
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
        throw ArgumentError('Unknown transfer status: $s');
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
