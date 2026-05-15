import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/api/api_error.dart';
import 'package:pdd_petty_cash/core/auth/token_store.dart';
import 'package:pdd_petty_cash/features/auth/data/api_auth_repository.dart';
import 'package:pdd_petty_cash/features/auth/data/auth_repository.dart';
import 'package:pdd_petty_cash/features/auth/domain/user.dart';

void main() {
  late InMemoryTokenStore tokens;
  late _FakeAdapter adapter;
  late Dio dio;
  late ApiAuthRepository repo;

  setUp(() {
    tokens = InMemoryTokenStore();
    adapter = _FakeAdapter();
    dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
    dio.httpClientAdapter = adapter;
    repo = ApiAuthRepository(dio: dio, tokens: tokens);
  });

  group('login', () {
    test('persists tokens and returns AuthSession on 200', () async {
      adapter.respond(
        path: '/api/v1/auth/login',
        status: 200,
        body: <String, dynamic>{
          'user': <String, dynamic>{
            'id': 'u-fatima',
            'username': 'fatima',
            'displayName': 'Fatima Al Hashimi',
            'displayNameAr': 'فاطمة الهاشمي',
            'email': 'fatima@protocol.gov.ae',
            'role': 'LEADER',
          },
          'tokens': <String, dynamic>{
            'accessToken': 'acc-1',
            'refreshToken': 'ref-1',
            'accessExpiresInSeconds': 900,
            'refreshExpiresInSeconds': 2592000,
          },
        },
      );

      final AuthSession session = await repo.login(
        username: 'fatima',
        password: 'demo1234',
      );

      expect(session.user.role, UserRole.leader);
      expect(session.user.displayNameAr, 'فاطمة الهاشمي');
      expect(session.accessToken, 'acc-1');

      final AuthTokens? stored = await tokens.read();
      expect(stored?.accessToken, 'acc-1');
      expect(stored?.refreshToken, 'ref-1');
    });

    test('throws ApiError with code on 401 invalid-credentials', () async {
      adapter.respond(
        path: '/api/v1/auth/login',
        status: 401,
        body: <String, dynamic>{
          'type': 'https://pdd.gov.ae/errors/auth/invalid-credentials',
          'title': 'Invalid username or password',
          'status': 401,
          'detail': 'The provided credentials are not valid.',
          'instance': '/api/v1/auth/login',
          'code': 'auth/invalid-credentials',
        },
      );

      await expectLater(
        repo.login(username: 'fatima', password: 'wrong'),
        throwsA(isA<ApiError>()
            .having((ApiError e) => e.code, 'code', 'auth/invalid-credentials')
            .having((ApiError e) => e.statusCode, 'statusCode', 401)),
      );

      expect(await tokens.read(), isNull);
    });

    test('throws ApiError with code on 400 validation', () async {
      adapter.respond(
        path: '/api/v1/auth/login',
        status: 400,
        body: <String, dynamic>{
          'title': 'Validation failed',
          'status': 400,
          'detail': 'One or more fields failed validation.',
          'code': 'validation/invalid-request',
        },
      );

      await expectLater(
        repo.login(username: '', password: 'x'),
        throwsA(isA<ApiError>().having((ApiError e) => e.isValidation, 'isValidation', true)),
      );
    });
  });

  group('currentUser', () {
    test('returns null when no tokens are stored', () async {
      expect(await repo.currentUser(), isNull);
    });

    test('returns user when /me returns 200', () async {
      await tokens.write(const AuthTokens(accessToken: 'a', refreshToken: 'r'));
      adapter.respond(
        path: '/api/v1/me',
        status: 200,
        body: <String, dynamic>{
          'id': 'u-noura',
          'username': 'noura',
          'displayName': 'Noura Al Falasi',
          'displayNameAr': 'نورة الفلاسي',
          'email': 'noura@protocol.gov.ae',
          'role': 'SUPER_ADMIN',
        },
      );

      final User? me = await repo.currentUser();
      expect(me?.role, UserRole.superAdmin);
    });

    test('clears tokens and returns null on 401', () async {
      await tokens.write(const AuthTokens(accessToken: 'a', refreshToken: 'r'));
      adapter.respondError(
        path: '/api/v1/me',
        status: 401,
        body: <String, dynamic>{
          'code': 'auth/unauthenticated',
          'title': 'Unauthenticated',
          'status': 401,
          'detail': 'Required.',
        },
      );

      final User? me = await repo.currentUser();
      expect(me, isNull);
      expect(await tokens.read(), isNull);
    });
  });

  group('logout', () {
    test('clears stored tokens', () async {
      await tokens.write(const AuthTokens(accessToken: 'a', refreshToken: 'r'));
      await repo.logout();
      expect(await tokens.read(), isNull);
    });
  });

  group('loginAsRole', () {
    test('is explicitly unsupported on the api impl', () async {
      expect(
        () => repo.loginAsRole(UserRole.admin),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

/// Minimal HttpClientAdapter that returns canned responses for given paths.
/// Each call pops the matching queued response; tests are linear.
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, List<_Canned>> _queue = <String, List<_Canned>>{};

  void respond({
    required String path,
    required int status,
    Map<String, dynamic>? body,
  }) {
    _queue.putIfAbsent(path, () => <_Canned>[]).add(_Canned(status, body));
  }

  /// Same as [respond] but the canned status is in the 4xx/5xx range so the
  /// outer Dio call throws a DioException — letting tests exercise the
  /// repository's catch-and-rethrow path.
  void respondError({
    required String path,
    required int status,
    Map<String, dynamic>? body,
  }) {
    _queue.putIfAbsent(path, () => <_Canned>[]).add(_Canned(status, body));
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final List<_Canned>? queued = _queue[options.path];
    if (queued == null || queued.isEmpty) {
      throw StateError('No canned response for ${options.method} ${options.path}');
    }
    final _Canned c = queued.removeAt(0);
    final List<int> bytes = utf8.encode(jsonEncode(c.body ?? const <String, dynamic>{}));
    return ResponseBody.fromBytes(
      bytes,
      c.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}

class _Canned {
  const _Canned(this.status, this.body);
  final int status;
  final Map<String, dynamic>? body;
}
