import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_store.dart';
import 'api_config.dart';
import 'api_error.dart';

/// Builds the singleton Dio instance every Api*Repository uses.
///
/// Two interceptors are wired up:
///   1. A request interceptor that adds `Authorization: Bearer <access>`
///      to every call that's not `/auth/login` or `/auth/refresh`.
///   2. A response interceptor that, on a 401 from a protected endpoint,
///      attempts a single refresh-token rotation and replays the original
///      request once. Concurrent 401s share the same refresh future so we
///      don't burn the refresh token N times for N parallel requests.
final Provider<Dio> dioProvider = Provider<Dio>((Ref ref) {
  final ApiConfig cfg = ref.watch(apiConfigProvider);
  final TokenStore tokens = ref.watch(tokenStoreProvider);

  final Dio dio = Dio(
    BaseOptions(
      baseUrl: cfg.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      contentType: 'application/json',
      responseType: ResponseType.json,
      // We handle non-2xx ourselves so the refresh interceptor sees them.
      validateStatus: (int? s) => s != null && s >= 200 && s < 600,
    ),
  );

  // Rebuild the base URL on the fly when the DevMenu flips it.
  void syncBaseUrl() {
    dio.options.baseUrl = cfg.baseUrl;
  }
  cfg.addListener(syncBaseUrl);
  ref.onDispose(() => cfg.removeListener(syncBaseUrl));

  dio.interceptors.add(_BearerInterceptor(tokens));
  dio.interceptors.add(_RefreshInterceptor(dio: dio, tokens: tokens));

  return dio;
});

class _BearerInterceptor extends Interceptor {
  _BearerInterceptor(this._tokens);
  final TokenStore _tokens;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isAuthEndpoint(options.path)) {
      return handler.next(options);
    }
    final AuthTokens? t = await _tokens.read();
    if (t != null) {
      options.headers['Authorization'] = 'Bearer ${t.accessToken}';
    }
    handler.next(options);
  }
}

class _RefreshInterceptor extends Interceptor {
  _RefreshInterceptor({required Dio dio, required TokenStore tokens})
      : _dio = dio,
        _tokens = tokens;

  final Dio _dio;
  final TokenStore _tokens;

  /// Single in-flight refresh shared by every parallel 401. Null when idle.
  Future<AuthTokens?>? _inflight;

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    if (response.statusCode != 401 || _isAuthEndpoint(response.requestOptions.path)) {
      // Non-401 success or 401 on /auth/* — surface as ApiError if not OK,
      // otherwise pass through.
      final int status = response.statusCode ?? 0;
      if (status >= 400) {
        return handler.reject(
          DioException(
            requestOptions: response.requestOptions,
            response: response,
            error: ApiError.fromResponse(response),
            type: DioExceptionType.badResponse,
          ),
        );
      }
      return handler.next(response);
    }

    // 401 on a protected endpoint: try a refresh and replay once.
    final AuthTokens? refreshed = await _refresh();
    if (refreshed == null) {
      // No refresh token or refresh failed — surface the original 401.
      return handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: ApiError.fromResponse(response),
          type: DioExceptionType.badResponse,
        ),
      );
    }

    final RequestOptions retry = response.requestOptions.copyWith();
    retry.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';
    try {
      final Response<dynamic> r = await _dio.fetch<dynamic>(retry);
      handler.resolve(r);
    } on DioException catch (e) {
      handler.reject(e);
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Network failures etc. — surface as ApiError consistently.
    handler.reject(
      err.copyWith(error: ApiError.fromResponse(err.response, cause: err)),
    );
  }

  Future<AuthTokens?> _refresh() {
    return _inflight ??= () async {
      try {
        final AuthTokens? current = await _tokens.read();
        if (current == null) return null;
        final Response<dynamic> resp = await _dio.post<dynamic>(
          '/api/v1/auth/refresh',
          data: <String, String>{'refreshToken': current.refreshToken},
          options: Options(headers: <String, dynamic>{'Authorization': null}),
        );
        if (resp.statusCode != 200) {
          await _tokens.clear();
          return null;
        }
        final Map<String, dynamic> body = (resp.data as Map<String, dynamic>);
        final Map<String, dynamic> t = body['tokens'] as Map<String, dynamic>;
        final AuthTokens fresh = AuthTokens(
          accessToken: t['accessToken'] as String,
          refreshToken: t['refreshToken'] as String,
        );
        await _tokens.write(fresh);
        return fresh;
      } catch (_) {
        await _tokens.clear();
        return null;
      } finally {
        _inflight = null;
      }
    }();
  }
}

bool _isAuthEndpoint(String path) {
  return path.endsWith('/auth/login') || path.endsWith('/auth/refresh');
}
