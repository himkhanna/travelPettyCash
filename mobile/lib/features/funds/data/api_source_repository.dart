import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../domain/funding.dart';
import 'funds_repository.dart';

class ApiSourceRepository implements SourceRepository {
  ApiSourceRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<List<Source>> all() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('/api/v1/sources');
      final List<dynamic> list = resp.data as List<dynamic>;
      return list
          .map((dynamic e) => _sourceFromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  Source _sourceFromJson(Map<String, dynamic> j) => Source(
        id: j['id'] as String,
        name: j['name'] as String,
        nameAr: j['nameAr'] as String,
        isActive: j['active'] as bool,
      );
}
