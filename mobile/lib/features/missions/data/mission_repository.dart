import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
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
      );
}
