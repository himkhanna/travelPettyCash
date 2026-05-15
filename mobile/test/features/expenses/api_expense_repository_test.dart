import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/api/api_error.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/features/expenses/data/api_category_repository.dart';
import 'package:pdd_petty_cash/features/expenses/data/api_expense_repository.dart';
import 'package:pdd_petty_cash/features/expenses/data/expense_repository.dart';
import 'package:pdd_petty_cash/features/expenses/domain/expense.dart';

void main() {
  late _FakeAdapter adapter;
  late ApiExpenseRepository expenseRepo;
  late ApiCategoryRepository categoryRepo;

  setUp(() {
    adapter = _FakeAdapter();
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
    dio.httpClientAdapter = adapter;
    expenseRepo = ApiExpenseRepository(dio: dio);
    categoryRepo = ApiCategoryRepository(dio: dio);
  });

  Map<String, dynamic> expJson({
    String id = 'e-1',
    String userId = 'u-ahmed',
    String sourceId = 'src-zabeel',
    String categoryCode = 'FOOD',
    int amount = 12300,
  }) =>
      <String, dynamic>{
        'id': id,
        'tripId': 'trip-ksa',
        'userId': userId,
        'sourceId': sourceId,
        'categoryCode': categoryCode,
        'amount': <String, dynamic>{'amount': amount, 'currency': 'SAR'},
        'quantity': 1,
        'details': 'Shawarma',
        'occurredAt': '2026-05-15T10:00:00Z',
        'receiptObjectKey': null,
        'createdAt': '2026-05-15T10:00:00Z',
        'updatedAt': null,
      };

  group('ApiCategoryRepository.all', () {
    test('parses category list', () async {
      adapter.respond(path: '/api/v1/categories', body: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'c1', 'code': 'FOOD', 'nameEn': 'Food',
          'nameAr': 'طعام', 'iconKey': 'cutlery', 'active': true,
        },
      ]);
      final List<ExpenseCategory> cats = await categoryRepo.all();
      expect(cats, hasLength(1));
      expect(cats.first.code, 'FOOD');
      expect(cats.first.nameAr, 'طعام');
    });
  });

  group('ApiExpenseRepository.list', () {
    test('parses Money + Bearer round-trips, passes filters as query', () async {
      adapter.respond(
        path: '/api/v1/trips/trip-ksa/expenses',
        body: <Map<String, dynamic>>[expJson()],
      );
      final List<Expense> rows = await expenseRepo.list(
        tripId: 'trip-ksa',
        userId: 'u-ahmed',
        filter: const ExpenseFilter(
          categoryCodes: <String>['FOOD'],
          sourceIds: <String>['src-zabeel'],
        ),
      );
      expect(rows, hasLength(1));
      expect(rows.first.amount.amountMinor, 12300);
      expect(adapter.lastQuery['userId'], 'u-ahmed');
      expect(adapter.lastQuery['categoryCode'], <String>['FOOD']);
      expect(adapter.lastQuery['sourceId'], <String>['src-zabeel']);
    });
  });

  group('ApiExpenseRepository.create', () {
    test('sends id, source, amount + Idempotency-Key', () async {
      adapter.respond(
        path: '/api/v1/trips/trip-ksa/expenses',
        body: expJson(),
      );
      final Expense e = await expenseRepo.create(
        clientUuid: 'e-1',
        tripId: 'trip-ksa',
        userId: 'u-ahmed',
        sourceId: 'src-zabeel',
        categoryCode: 'FOOD',
        amount: const Money(12300, 'SAR'),
        details: 'Shawarma',
        occurredAt: DateTime.utc(2026, 5, 15, 10),
        idempotencyKey: 'idem-1',
      );
      expect(e.id, 'e-1');
      expect(adapter.lastHeaders['Idempotency-Key'], 'idem-1');
      expect(adapter.lastBody['id'], 'e-1');
      expect((adapter.lastBody['amount'] as Map<String, dynamic>)['amount'], 12300);
    });

    test('400 missing-idempotency-key surfaces as ApiError', () async {
      adapter.respond(
        path: '/api/v1/trips/trip-ksa/expenses',
        status: 400,
        body: <String, dynamic>{
          'code': 'validation/missing-idempotency-key',
          'title': 'Missing Idempotency-Key',
          'status': 400,
          'detail': 'Required.',
        },
      );
      await expectLater(
        expenseRepo.create(
          clientUuid: 'e-2', tripId: 'trip-ksa', userId: 'u-ahmed',
          sourceId: 'src-zabeel', categoryCode: 'FOOD',
          amount: const Money(100, 'SAR'),
          details: '', occurredAt: DateTime.utc(2026, 5, 15),
          idempotencyKey: '',
        ),
        throwsA(isA<ApiError>().having(
          (ApiError e) => e.code, 'code', 'validation/missing-idempotency-key',
        )),
      );
    });
  });

  group('ApiExpenseRepository.reassignSource', () {
    test('PATCHes new sourceId', () async {
      adapter.respond(
        path: '/api/v1/expenses/e-1/source',
        body: expJson(sourceId: 'src-protocol'),
      );
      final Expense e = await expenseRepo.reassignSource('e-1', 'src-protocol');
      expect(e.sourceId, 'src-protocol');
      expect(adapter.lastBody['sourceId'], 'src-protocol');
    });
  });

  group('ApiExpenseRepository.summary', () {
    test('parses bilingual labels', () async {
      adapter.respond(
        path: '/api/v1/trips/trip-ksa/expenses/summary',
        body: <String, dynamic>{
          'groupBy': 'category',
          'scope': 'trip',
          'rows': <Map<String, dynamic>>[
            <String, dynamic>{
              'key': 'FOOD',
              'labelEn': 'Food',
              'labelAr': 'طعام',
              'amount': <String, dynamic>{'amount': 50000, 'currency': 'SAR'},
            },
          ],
        },
      );
      final List<ExpenseSummary> rows = await expenseRepo.summary(
        tripId: 'trip-ksa',
        scope: ExpenseSummaryScope.all,
        groupBy: ExpenseGroupBy.category,
      );
      expect(rows, hasLength(1));
      expect(rows.first.label, 'Food');
      expect(rows.first.amount.amountMinor, 50000);
      expect(adapter.lastQuery['scope'], 'trip');
      expect(adapter.lastQuery['groupBy'], 'category');
    });
  });

  group('ApiExpenseRepository.uploadReceipt', () {
    test('is explicitly unsupported in this slice', () async {
      expect(
        () => expenseRepo.uploadReceipt(
          'e-1',
          const ReceiptUpload(
            localPath: '/tmp/r.jpg',
            mime: 'image/jpeg',
            sha256: 'abc',
            byteSize: 1234,
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

class _FakeAdapter implements HttpClientAdapter {
  final Map<String, _Canned> _byPath = <String, _Canned>{};
  Map<String, dynamic> lastQuery = <String, dynamic>{};
  Map<String, dynamic> lastHeaders = <String, dynamic>{};
  Map<String, dynamic> lastBody = <String, dynamic>{};

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
    if (options.data is Map<String, dynamic>) {
      lastBody = Map<String, dynamic>.from(options.data as Map<String, dynamic>);
    } else {
      lastBody = <String, dynamic>{};
    }
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
