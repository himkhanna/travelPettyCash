import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fake/fake_config.dart';

/// Thin Dio wrapper that auto-injects the JWT and base URL from FakeConfig.
/// Rebuilt whenever backendMode / backendBaseUrl / authToken change so
/// flipping the landing toggle takes effect immediately.
class ApiClient {
  ApiClient(this._cfg) {
    _dio = Dio(BaseOptions(
      baseUrl: _cfg.backendBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        if (_cfg.authToken != null) {
          options.headers['Authorization'] = 'Bearer ${_cfg.authToken}';
        }
        handler.next(options);
      },
    ));
  }

  final FakeConfig _cfg;
  late final Dio _dio;

  Dio get raw => _dio;

  Future<T> get<T>(String path, {Map<String, Object?>? query}) async {
    final Response<dynamic> r = await _dio.get<dynamic>(path,
        queryParameters: query?.cast<String, dynamic>());
    return r.data as T;
  }

  Future<T> post<T>(String path, {Object? body}) async {
    final Response<dynamic> r = await _dio.post<dynamic>(path, data: body);
    return r.data as T;
  }

  Future<T> put<T>(String path, {Object? body}) async {
    final Response<dynamic> r = await _dio.put<dynamic>(path, data: body);
    return r.data as T;
  }

  Future<T> patch<T>(String path, {Object? body}) async {
    final Response<dynamic> r = await _dio.patch<dynamic>(path, data: body);
    return r.data as T;
  }

  /// Direct byte download for report endpoints.
  Future<({List<int> bytes, String? filename, String? contentType})>
      downloadBytes(String path, {Map<String, Object?>? query}) async {
    final Response<List<int>> r = await _dio.get<List<int>>(
      path,
      queryParameters: query?.cast<String, dynamic>(),
      options: Options(responseType: ResponseType.bytes),
    );
    String? filename;
    final String? cd = r.headers.value('content-disposition');
    if (cd != null) {
      final RegExpMatch? m = RegExp(r'filename="?([^";]+)').firstMatch(cd);
      if (m != null) filename = m.group(1);
    }
    return (
      bytes: r.data ?? <int>[],
      filename: filename,
      contentType: r.headers.value('content-type'),
    );
  }
}

/// Rebuilt whenever FakeConfig fires (latency knob, role, etc.) — Dio's
/// baseUrl is captured at construction, so reconstructing on every notify
/// keeps the base URL in sync with the landing-page toggle.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((Ref ref) {
  final FakeConfig cfg = ref.watch(fakeConfigProvider);
  // Listen to FakeConfig changes so Riverpod rebuilds this provider when the
  // user flips backend mode or signs in/out.
  cfg.addListener(ref.invalidateSelf);
  ref.onDispose(() => cfg.removeListener(ref.invalidateSelf));
  return ApiClient(cfg);
});
