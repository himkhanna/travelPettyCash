import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../domain/insight.dart';
import 'insights_repository.dart';

/// Calls the backend's GET /api/v1/trips/{id}/insights, which runs the
/// deterministic insights engine and returns pre-rendered observations.
class ApiInsightsRepository implements InsightsRepository {
  ApiInsightsRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<TripInsights> forTrip(String tripId) async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('/api/v1/trips/$tripId/insights');
      return TripInsights.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }
}
