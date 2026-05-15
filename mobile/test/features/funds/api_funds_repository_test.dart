import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/api/api_error.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/features/funds/data/api_allocation_repository.dart';
import 'package:pdd_petty_cash/features/funds/data/api_transfer_repository.dart';
import 'package:pdd_petty_cash/features/funds/domain/funding.dart';
import 'package:pdd_petty_cash/features/funds/domain/funds_calculations.dart';

void main() {
  late _FakeAdapter adapter;
  late Dio dio;
  late ApiAllocationRepository allocRepo;
  late ApiTransferRepository xferRepo;

  setUp(() {
    adapter = _FakeAdapter();
    dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
    dio.httpClientAdapter = adapter;
    allocRepo = ApiAllocationRepository(dio: dio);
    xferRepo = ApiTransferRepository(dio: dio);
  });

  Map<String, dynamic> allocJson({
    String id = 'a-1',
    String status = 'PENDING',
    String? fromUserId = 'u-admin',
    String toUserId = 'u-fatima',
  }) =>
      <String, dynamic>{
        'id': id,
        'tripId': 'trip-ksa',
        'fromUserId': fromUserId,
        'toUserId': toUserId,
        'sourceId': 'src-zabeel',
        'amount': <String, dynamic>{'amount': 500000, 'currency': 'SAR'},
        'status': status,
        'note': null,
        'createdAt': '2026-05-15T10:00:00Z',
        'respondedAt': null,
      };

  group('AllocationRepository createMany', () {
    test('sends rows + Idempotency-Key header; parses array response', () async {
      adapter.respond(
        path: '/api/v1/trips/trip-ksa/allocations',
        body: <Map<String, dynamic>>[allocJson()],
      );

      final List<Allocation> created = await allocRepo.createMany(
        tripId: 'trip-ksa',
        idempotencyKey: 'key-1',
        rows: <AllocationDraftRow>[
          AllocationDraftRow(
            toUserId: 'u-fatima',
            sourceId: 'src-zabeel',
            amount: const Money(500000, 'SAR'),
          ),
        ],
      );
      expect(created, hasLength(1));
      expect(created.first.amount.amountMinor, 500000);
      expect(adapter.lastHeaders['Idempotency-Key'], 'key-1');
    });

    test('surfaces 403 as ApiError(isForbidden=true)', () async {
      adapter.respond(
        path: '/api/v1/trips/trip-ksa/allocations',
        status: 403,
        body: <String, dynamic>{
          'code': 'auth/forbidden',
          'title': 'Forbidden',
          'status': 403,
          'detail': 'Members cannot allocate',
        },
      );
      await expectLater(
        allocRepo.createMany(
          tripId: 'trip-ksa',
          idempotencyKey: 'k',
          rows: <AllocationDraftRow>[
            AllocationDraftRow(
              toUserId: 'u-fatima',
              sourceId: 'src-zabeel',
              amount: const Money(100, 'SAR'),
            ),
          ],
        ),
        throwsA(isA<ApiError>().having((ApiError e) => e.isForbidden, 'isForbidden', true)),
      );
    });
  });

  group('AllocationRepository respond', () {
    test('rounds-trips ACCEPTED', () async {
      adapter.respond(
        path: '/api/v1/allocations/a-1/respond',
        body: allocJson(id: 'a-1', status: 'ACCEPTED'),
      );
      final Allocation a = await allocRepo.respond(
        allocationId: 'a-1',
        response: AllocationStatus.accepted,
      );
      expect(a.status, AllocationStatus.accepted);
    });
  });

  group('AllocationRepository forTrip', () {
    test('passes memberId as query param when given', () async {
      adapter.respond(
        path: '/api/v1/trips/trip-ksa/allocations',
        body: <Map<String, dynamic>>[],
      );
      await allocRepo.forTrip('trip-ksa', memberId: 'u-fatima');
      expect(adapter.lastQuery['memberId'], 'u-fatima');
    });
  });

  group('TransferRepository create', () {
    test('sends amount, sourceId, note + Idempotency-Key', () async {
      adapter.respond(
        path: '/api/v1/trips/trip-ksa/transfers',
        body: <String, dynamic>{
          'id': 'x-1',
          'tripId': 'trip-ksa',
          'fromUserId': 'u-fatima',
          'toUserId': 'u-ahmed',
          'sourceId': 'src-zabeel',
          'amount': <String, dynamic>{'amount': 25000, 'currency': 'SAR'},
          'status': 'PENDING',
          'note': 'lunch',
          'createdAt': '2026-05-15T10:00:00Z',
          'respondedAt': null,
        },
      );
      final Transfer t = await xferRepo.create(
        clientUuid: 'cli-1',
        tripId: 'trip-ksa',
        fromUserId: 'u-fatima',
        toUserId: 'u-ahmed',
        sourceId: 'src-zabeel',
        amount: const Money(25000, 'SAR'),
        note: 'lunch',
        idempotencyKey: 'xk-1',
      );
      expect(t.id, 'x-1');
      expect(t.amount.amountMinor, 25000);
      expect(adapter.lastHeaders['Idempotency-Key'], 'xk-1');
    });

    test('surfaces 400 missing-idempotency-key as ApiError', () async {
      adapter.respond(
        path: '/api/v1/trips/trip-ksa/transfers',
        status: 400,
        body: <String, dynamic>{
          'code': 'validation/missing-idempotency-key',
          'title': 'Missing Idempotency-Key',
          'status': 400,
          'detail': 'Required.',
        },
      );
      await expectLater(
        xferRepo.create(
          clientUuid: 'c', tripId: 'trip-ksa',
          fromUserId: 'u-fatima', toUserId: 'u-ahmed',
          sourceId: 'src-zabeel',
          amount: const Money(100, 'SAR'),
          idempotencyKey: '',
        ),
        throwsA(isA<ApiError>().having(
          (ApiError e) => e.code, 'code', 'validation/missing-idempotency-key',
        )),
      );
    });
  });

  group('computeLeaderAvailableBySource', () {
    test('admin pool in - outgoing alloc - expenses = available', () {
      final Map<String, Money> available = computeLeaderAvailableBySource(
        allocations: <Allocation>[
          // Admin → leader, accepted: +1,000,000
          Allocation(
            id: 'a1', tripId: 't', fromUserId: null, toUserId: 'leader',
            sourceId: 'src1',
            amount: const Money(1000000, 'SAR'),
            status: AllocationStatus.accepted,
            createdAt: DateTime.parse('2026-05-01T00:00:00Z'),
          ),
          // Leader → member, pending: -200,000
          Allocation(
            id: 'a2', tripId: 't', fromUserId: 'leader', toUserId: 'member',
            sourceId: 'src1',
            amount: const Money(200000, 'SAR'),
            status: AllocationStatus.pending,
            createdAt: DateTime.parse('2026-05-02T00:00:00Z'),
          ),
          // Leader → member, declined: ignored
          Allocation(
            id: 'a3', tripId: 't', fromUserId: 'leader', toUserId: 'member',
            sourceId: 'src1',
            amount: const Money(50000, 'SAR'),
            status: AllocationStatus.declined,
            createdAt: DateTime.parse('2026-05-03T00:00:00Z'),
          ),
        ],
        leaderId: 'leader',
        currency: 'SAR',
        leaderExpenses: <({String sourceId, Money amount})>[
          (sourceId: 'src1', amount: const Money(75000, 'SAR')),
        ],
      );
      expect(available['src1']?.amountMinor, 1000000 - 200000 - 75000);
    });
  });
}

class _FakeAdapter implements HttpClientAdapter {
  final Map<String, _Canned> _byPath = <String, _Canned>{};
  Map<String, dynamic> lastQuery = <String, dynamic>{};
  Map<String, dynamic> lastHeaders = <String, dynamic>{};

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
    lastHeaders = Map<String, dynamic>.from(options.headers);
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
