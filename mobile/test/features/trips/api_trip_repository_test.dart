import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/api/api_error.dart';
import 'package:pdd_petty_cash/features/trips/data/api_trip_repository.dart';
import 'package:pdd_petty_cash/features/trips/domain/trip.dart';

void main() {
  late _FakeAdapter adapter;
  late ApiTripRepository repo;

  setUp(() {
    adapter = _FakeAdapter();
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
    dio.httpClientAdapter = adapter;
    repo = ApiTripRepository(dio: dio);
  });

  Map<String, dynamic> ksaTrip() => <String, dynamic>{
        'id': 'trip-ksa',
        'name': 'KSA State Visit',
        'countryCode': 'SA',
        'countryName': 'Saudi Arabia',
        'currency': 'SAR',
        'status': 'ACTIVE',
        'createdBy': 'u-khalid',
        'leaderId': 'u-fatima',
        'memberIds': <String>['u-ahmed', 'u-mohammed', 'u-layla'],
        'totalBudget': <String, dynamic>{
          'amount': 9100000,
          'currency': 'SAR',
        },
        'createdAt': '2026-04-28T05:00:00Z',
        'closedAt': null,
      };

  group('activeTrips', () {
    test('parses Money via minor units and exposes memberIds', () async {
      adapter.respond(
        path: '/api/v1/trips',
        body: <Map<String, dynamic>>[ksaTrip()],
      );
      final List<Trip> trips = await repo.activeTrips();
      expect(trips, hasLength(1));
      final Trip t = trips.single;
      expect(t.id, 'trip-ksa');
      expect(t.status, TripStatus.active);
      expect(t.totalBudget.amountMinor, 9100000);
      expect(t.totalBudget.currencyCode, 'SAR');
      expect(t.memberIds, containsAll(<String>['u-ahmed', 'u-mohammed', 'u-layla']));
    });

    test('passes status filter as query parameter', () async {
      adapter.respond(
        path: '/api/v1/trips',
        body: <Map<String, dynamic>>[],
      );
      await repo.allTrips(status: TripStatus.closed);
      expect(adapter.lastQuery['status'], 'CLOSED');
    });
  });

  group('tripById', () {
    test('parses a single Trip', () async {
      adapter.respond(path: '/api/v1/trips/trip-ksa', body: ksaTrip());
      final Trip t = await repo.tripById('trip-ksa');
      expect(t.leaderId, 'u-fatima');
    });

    test('surfaces 404 as ApiError(code=trips/not-found)', () async {
      adapter.respond(
        path: '/api/v1/trips/missing',
        status: 404,
        body: <String, dynamic>{
          'code': 'trips/not-found',
          'title': 'Trip not found',
          'status': 404,
          'detail': 'No trip with id missing',
        },
      );
      await expectLater(
        repo.tripById('missing'),
        throwsA(isA<ApiError>().having((ApiError e) => e.code, 'code', 'trips/not-found')),
      );
    });
  });

  group('balances', () {
    test('parses headline totals + per-source list', () async {
      adapter.respond(
        path: '/api/v1/trips/trip-ksa/balances',
        body: <String, dynamic>{
          'tripId': 'trip-ksa',
          'scope': 'trip',
          'totalBudget': <String, dynamic>{'amount': 9100000, 'currency': 'SAR'},
          'totalSpent': <String, dynamic>{'amount': 0, 'currency': 'SAR'},
          'totalBalance': <String, dynamic>{'amount': 9100000, 'currency': 'SAR'},
          'perSource': <Map<String, dynamic>>[
            <String, dynamic>{
              'sourceId': 'src-zabeel',
              'sourceName': 'Zabeel Office',
              'sourceNameAr': 'قصر زعبيل',
              'received': <String, dynamic>{'amount': 0, 'currency': 'SAR'},
              'spent': <String, dynamic>{'amount': 0, 'currency': 'SAR'},
              'balance': <String, dynamic>{'amount': 0, 'currency': 'SAR'},
            }
          ],
        },
      );
      final TripBalances b = await repo.balances('trip-ksa', BalanceScope.trip);
      expect(b.totalBudget.amountMinor, 9100000);
      expect(b.perSource, hasLength(1));
      expect(b.perSource.first.sourceNameAr, 'قصر زعبيل');
    });
  });

  group('createTrip', () {
    test('returns the new Trip on 200', () async {
      adapter.respond(
        path: '/api/v1/trips',
        body: <String, dynamic>{
          ...ksaTrip(),
          'id': 'trip-new',
          'name': 'Doha Visit',
        },
      );
      final Trip t = await repo.createTrip(
        name: 'Doha Visit',
        countryCode: 'QA',
        currency: 'QAR',
        leaderId: 'u-fatima',
        memberIds: <String>['u-ahmed'],
      );
      expect(t.id, 'trip-new');
    });

    test('surfaces 403 as ApiError(isForbidden=true)', () async {
      adapter.respond(
        path: '/api/v1/trips',
        status: 403,
        body: <String, dynamic>{
          'code': 'auth/forbidden',
          'title': 'Forbidden',
          'status': 403,
          'detail': 'Only admins.',
        },
      );
      await expectLater(
        repo.createTrip(
          name: 'X',
          countryCode: 'AE',
          currency: 'AED',
          leaderId: 'u-fatima',
          memberIds: <String>[],
        ),
        throwsA(isA<ApiError>().having((ApiError e) => e.isForbidden, 'isForbidden', true)),
      );
    });
  });

  group('closeTrip', () {
    test('returns the closed Trip', () async {
      adapter.respond(
        path: '/api/v1/trips/trip-ksa/close',
        body: <String, dynamic>{
          ...ksaTrip(),
          'status': 'CLOSED',
          'closedAt': '2026-05-15T10:00:00Z',
        },
      );
      final Trip t = await repo.closeTrip('trip-ksa');
      expect(t.status, TripStatus.closed);
      expect(t.closedAt, isNotNull);
    });
  });
}

/// Minimal HttpClientAdapter with canned responses. Records the last query
/// params so tests can assert query-string mapping.
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, _Canned> _byPath = <String, _Canned>{};
  Map<String, dynamic> lastQuery = <String, dynamic>{};

  void respond({
    required String path,
    int status = 200,
    required Object body,
  }) {
    _byPath[path] = _Canned(status, body);
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastQuery = Map<String, dynamic>.from(options.queryParameters);
    final _Canned? c = _byPath[options.path];
    if (c == null) {
      throw StateError('No canned response for ${options.method} ${options.path}');
    }
    final List<int> bytes = utf8.encode(jsonEncode(c.body));
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
  final Object body;
}
