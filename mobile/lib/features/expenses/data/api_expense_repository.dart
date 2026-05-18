import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';
import '../../../core/money/money.dart';
import '../domain/expense.dart';
import 'expense_repository.dart';

class ApiExpenseRepository implements ExpenseRepository {
  ApiExpenseRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<List<Expense>> list({
    required String tripId,
    String? userId,
    ExpenseFilter? filter,
    String? cursor,
    int limit = 20,
  }) async {
    final Map<String, dynamic> query = <String, dynamic>{};
    if (userId != null) query['userId'] = userId;
    if (filter != null) {
      if (filter.categoryCodes != null) query['categoryCode'] = filter.categoryCodes;
      if (filter.sourceIds != null) query['sourceId'] = filter.sourceIds;
      if (filter.memberIds != null) query['memberId'] = filter.memberIds;
      if (filter.from != null) query['from'] = filter.from!.toUtc().toIso8601String();
      if (filter.to != null) query['to'] = filter.to!.toUtc().toIso8601String();
    }
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/trips/$tripId/expenses',
        queryParameters: query,
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => _expenseFromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<Expense> byId(String expenseId) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('/api/v1/expenses/$expenseId');
      return _expenseFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<Expense> create({
    required String clientUuid,
    required String tripId,
    required String userId,
    required String sourceId,
    required String categoryCode,
    required Money amount,
    required String details,
    required DateTime occurredAt,
    int quantity = 1,
    String? receiptObjectKey,
    required String idempotencyKey,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/trips/$tripId/expenses',
        data: <String, dynamic>{
          'id': clientUuid,
          'sourceId': sourceId,
          'categoryCode': categoryCode,
          'amount': <String, dynamic>{
            'amount': amount.amountMinor,
            'currency': amount.currencyCode,
          },
          'quantity': quantity,
          'details': details,
          'occurredAt': occurredAt.toUtc().toIso8601String(),
          if (receiptObjectKey != null) 'receiptObjectKey': receiptObjectKey,
        },
        options: Options(headers: <String, dynamic>{
          'Idempotency-Key': idempotencyKey,
        }),
      );
      return _expenseFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<Expense> update(String expenseId, ExpensePatch patch) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    if (patch.categoryCode != null) body['categoryCode'] = patch.categoryCode;
    if (patch.amount != null) {
      body['amount'] = <String, dynamic>{
        'amount': patch.amount!.amountMinor,
        'currency': patch.amount!.currencyCode,
      };
    }
    if (patch.details != null) body['details'] = patch.details;
    if (patch.occurredAt != null) {
      body['occurredAt'] = patch.occurredAt!.toUtc().toIso8601String();
    }
    try {
      final Response<dynamic> resp = await _dio.patch<dynamic>(
        '/api/v1/expenses/$expenseId',
        data: body,
      );
      return _expenseFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<Expense> reassignSource(String expenseId, String newSourceId) async {
    try {
      final Response<dynamic> resp = await _dio.patch<dynamic>(
        '/api/v1/expenses/$expenseId/source',
        data: <String, String>{'sourceId': newSourceId},
      );
      return _expenseFromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<List<Expense>> bulkReassignSource(Map<String, String> idToSourceId) async {
    // The backend doesn't yet expose a bulk endpoint — do single calls in
    // sequence. When the volume justifies it, add POST /expenses:bulk-reassign.
    final List<Expense> out = <Expense>[];
    for (final MapEntry<String, String> e in idToSourceId.entries) {
      out.add(await reassignSource(e.key, e.value));
    }
    return out;
  }

  @override
  Future<String> uploadReceipt(String expenseId, ReceiptUpload upload) async {
    // On Flutter Web, upload.localPath is a `blob:` URL that
    // MultipartFile.fromFile can't read. Prefer in-memory bytes when the
    // caller provided them — the picker reads them via XFile.readAsBytes.
    final MultipartFile filePart = upload.bytes != null
        ? MultipartFile.fromBytes(
            upload.bytes!,
            filename: upload.filename ?? 'receipt',
            contentType: DioMediaType.parse(upload.mime),
          )
        : await MultipartFile.fromFile(
            upload.localPath,
            contentType: DioMediaType.parse(upload.mime),
          );
    final FormData form = FormData.fromMap(<String, dynamic>{
      'file': filePart,
    });
    try {
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/api/v1/expenses/$expenseId/receipt',
        data: form,
      );
      return (resp.data as Map<String, dynamic>)['receiptObjectKey'] as String;
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  /// Presigned GET URL for the receipt attached to this expense — the client
  /// renders the image directly from MinIO without proxying through the
  /// backend. Short TTL (5 min server-side); refetch when stale. Throws
  /// [ApiError] with code {@code expenses/no-receipt} if none is set.
  @override
  Future<String> receiptUrl(String expenseId) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/expenses/$expenseId/receipt',
      );
      return (resp.data as Map<String, dynamic>)['url'] as String;
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  @override
  Future<List<ExpenseSummary>> summary({
    required String tripId,
    required ExpenseSummaryScope scope,
    required ExpenseGroupBy groupBy,
    String? userId,
  }) async {
    final Map<String, dynamic> query = <String, dynamic>{
      'scope': _scopeToApi(scope),
      'groupBy': _groupByToApi(groupBy),
    };
    if (userId != null) query['userId'] = userId;
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '/api/v1/trips/$tripId/expenses/summary',
        queryParameters: query,
      );
      final Map<String, dynamic> body = resp.data as Map<String, dynamic>;
      final List<dynamic> rows = body['rows'] as List<dynamic>;
      return rows
          .map((dynamic r) => _summaryFromJson(r as Map<String, dynamic>))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiError.fromResponse(e.response, cause: e);
    }
  }

  Expense _expenseFromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> amount = j['amount'] as Map<String, dynamic>;
    return Expense(
      id: j['id'] as String,
      tripId: j['tripId'] as String,
      userId: j['userId'] as String,
      sourceId: j['sourceId'] as String,
      categoryCode: j['categoryCode'] as String,
      amount: Money(amount['amount'] as int, amount['currency'] as String),
      quantity: j['quantity'] as int,
      details: (j['details'] as String?) ?? '',
      occurredAt: DateTime.parse(j['occurredAt'] as String),
      createdAt: DateTime.parse(j['createdAt'] as String),
      receiptObjectKey: j['receiptObjectKey'] as String?,
      updatedAt: j['updatedAt'] == null
          ? null
          : DateTime.parse(j['updatedAt'] as String),
    );
  }

  ExpenseSummary _summaryFromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> amount = j['amount'] as Map<String, dynamic>;
    return ExpenseSummary(
      groupKey: j['key'] as String,
      label: j['labelEn'] as String,
      amount: Money(amount['amount'] as int, amount['currency'] as String),
    );
  }

  String _scopeToApi(ExpenseSummaryScope s) {
    switch (s) {
      case ExpenseSummaryScope.mine:
        return 'mine';
      case ExpenseSummaryScope.user:
        return 'user';
      case ExpenseSummaryScope.all:
        return 'trip';
    }
  }

  String _groupByToApi(ExpenseGroupBy g) {
    switch (g) {
      case ExpenseGroupBy.category:
        return 'category';
      case ExpenseGroupBy.source:
        return 'source';
      case ExpenseGroupBy.member:
        return 'member';
    }
  }
}
