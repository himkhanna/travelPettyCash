import 'package:dio/dio.dart';

/// Domain-flavoured error parsed from an RFC 7807 ProblemDetail body
/// (CLAUDE.md §9). Plays nicely with `catch (ApiError e)` in repository
/// callers and exposes the stable [code] for client logic / UI strings.
class ApiError implements Exception {
  ApiError({
    required this.statusCode,
    required this.code,
    required this.title,
    required this.detail,
  });

  /// Maps a Dio response to an ApiError. Falls back to generic fields if the
  /// server returned something that wasn't a ProblemDetail (e.g. 502 HTML).
  factory ApiError.fromResponse(Response<dynamic>? response, {Object? cause}) {
    final int status = response?.statusCode ?? 0;
    final Object? body = response?.data;
    if (body is Map<String, dynamic>) {
      final String? code = body['code'] as String?;
      final String? title = body['title'] as String?;
      final String? detail = body['detail'] as String?;
      return ApiError(
        statusCode: status,
        code: code ?? _fallbackCode(status, cause),
        title: title ?? 'Request failed',
        detail: detail ?? cause?.toString() ?? 'No detail',
      );
    }
    return ApiError(
      statusCode: status,
      code: _fallbackCode(status, cause),
      title: 'Request failed',
      detail: cause?.toString() ?? body?.toString() ?? 'No detail',
    );
  }

  final int statusCode;
  final String code;
  final String title;
  final String detail;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isValidation => code == 'validation/invalid-request';

  @override
  String toString() => 'ApiError($statusCode, $code): $detail';

  static String _fallbackCode(int status, Object? cause) {
    if (cause is DioException) {
      return switch (cause.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => 'network/timeout',
        DioExceptionType.connectionError => 'network/unreachable',
        DioExceptionType.cancel => 'network/cancelled',
        _ => 'http/$status',
      };
    }
    return 'http/$status';
  }
}
