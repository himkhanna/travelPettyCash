import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../domain/expense.dart';
import 'category_repository.dart';

class ApiCategoryRepository implements CategoryRepository {
  ApiCategoryRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<List<ExpenseCategory>> all() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('/api/v1/categories');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<ExpenseCategory> create({
    required String code,
    required String nameEn,
    required String nameAr,
    required String iconKey,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/categories',
        data: <String, dynamic>{
          'code': code,
          'nameEn': nameEn,
          'nameAr': nameAr,
          'iconKey': iconKey,
        },
      );
      return _fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  ExpenseCategory _fromJson(Map<String, dynamic> j) => ExpenseCategory(
        code: j['code'] as String,
        nameEn: j['nameEn'] as String,
        nameAr: j['nameAr'] as String,
        iconKey: j['iconKey'] as String,
        isActive: j['active'] as bool? ?? true,
      );
}
