import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../../../core/money/money.dart';
import '../domain/mission.dart';

class MissionRepository {
  MissionRepository({required Dio dio}) : _dio = dio;
  final Dio _dio;

  Future<List<Mission>> list() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('/api/v1/missions');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  /// Admin/Super only on the server. Code is auto-generated when omitted.
  Future<Mission> create({
    required String name,
    String? nameAr,
    String? code,
    String? description,
    String? parentMissionId,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/missions',
        data: <String, dynamic>{
          'name': name,
          if (nameAr != null && nameAr.isNotEmpty) 'nameAr': nameAr,
          if (code != null && code.isNotEmpty) 'code': code,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (parentMissionId != null) 'parentMissionId': parentMissionId,
        },
      );
      return _fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  /// Admin/Super only on the server. All editable fields are required so
  /// the caller can't accidentally null out a name by omitting it from the
  /// payload — the CMS edit screen passes the current values for unchanged
  /// fields. `parentMissionId` is sent as `null` to detach from a parent.
  Future<Mission> update({
    required String id,
    required String name,
    String? nameAr,
    String? description,
    String? parentMissionId,
    required MissionStatus status,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.put<dynamic>(
        '/api/v1/missions/$id',
        data: <String, dynamic>{
          'name': name,
          'nameAr': nameAr,
          'description': description,
          'parentMissionId': parentMissionId,
          'status': status == MissionStatus.closed ? 'CLOSED' : 'ACTIVE',
        },
      );
      return _fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  /// Admin only on the server. Sets the mission-level budget (BRD §2.2)
  /// and returns the updated mission. [amountMinor] is in integer minor
  /// units (e.g. fils/halalas); [currency] is the ISO 4217 code.
  Future<Mission> setBudget(
    String missionId,
    int amountMinor,
    String currency,
  ) async {
    try {
      final Response<dynamic> resp = await _dio.patch<dynamic>(
        '/api/v1/missions/$missionId/budget',
        data: <String, dynamic>{
          'amount': amountMinor,
          'currency': currency,
        },
      );
      return _fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  /// Server rejects (409) when the mission still has trips attached or any
  /// child missions. The CMS screen surfaces the detail string from the
  /// 7807 envelope so the admin knows what to clean up first.
  Future<void> delete(String id) async {
    try {
      await _dio.delete<dynamic>('/api/v1/missions/$id');
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  Mission _fromJson(Map<String, dynamic> j) => Mission(
        id: j['id'] as String,
        name: j['name'] as String,
        nameAr: j['nameAr'] as String?,
        code: j['code'] as String,
        description: j['description'] as String?,
        parentMissionId: j['parentMissionId'] as String?,
        status: MissionStatus.fromWire(j['status'] as String),
        createdById: j['createdById'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        closedAt: j['closedAt'] == null
            ? null
            : DateTime.parse(j['closedAt'] as String),
        budget: j['budget'] == null
            ? null
            : _moneyFromJson(j['budget'] as Map<String, dynamic>),
      );

  Money _moneyFromJson(Map<String, dynamic> j) =>
      Money(j['amount'] as int, j['currency'] as String);
}
