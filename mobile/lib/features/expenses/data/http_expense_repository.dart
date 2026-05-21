import '../../../core/api/api_client.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../domain/expense.dart';
import 'expense_repository.dart';
import 'fake_expense_repository.dart';

/// HTTP repo for /api/v1/trips/{id}/expenses + /api/v1/expenses/{id}.
/// Bulk-source reassign, summary, and receipt upload fall back to
/// FakeExpenseRepository because the backend does not yet expose them.
class HttpExpenseRepository implements ExpenseRepository {
  HttpExpenseRepository(this._api, this._store, FakeExpenseRepository fake)
      : _fake = fake;

  final ApiClient _api;
  final DemoStore _store;
  final FakeExpenseRepository _fake;

  @override
  Future<List<Expense>> list({
    required String tripId,
    String? userId,
    ExpenseFilter? filter,
    String? cursor,
    int limit = 20,
  }) async {
    final List<dynamic> raw = await _api.get<List<dynamic>>(
      '/api/v1/trips/$tripId/expenses',
    );
    Iterable<Expense> rows = raw
        .cast<Map<String, dynamic>>()
        .map(_parseExpense);
    if (userId != null) {
      rows = rows.where((Expense e) => e.userId == userId);
    }
    if (filter != null) {
      if (filter.categoryCodes != null && filter.categoryCodes!.isNotEmpty) {
        rows = rows.where(
          (Expense e) => filter.categoryCodes!.contains(e.categoryCode),
        );
      }
      if (filter.sourceIds != null && filter.sourceIds!.isNotEmpty) {
        rows = rows.where((Expense e) => filter.sourceIds!.contains(e.sourceId));
      }
      if (filter.memberIds != null && filter.memberIds!.isNotEmpty) {
        rows = rows.where((Expense e) => filter.memberIds!.contains(e.userId));
      }
      if (filter.from != null) {
        rows = rows.where((Expense e) => !e.occurredAt.isBefore(filter.from!));
      }
      if (filter.to != null) {
        rows = rows.where((Expense e) => !e.occurredAt.isAfter(filter.to!));
      }
    }
    return rows.toList(growable: false);
  }

  @override
  Future<Expense> byId(String expenseId) async {
    // No single-expense endpoint yet — pull the parent trip's list and find.
    // Acceptable for the prototype; revisit once we wire /expenses/{id} GET.
    final Expense? found = _store.expenses
        .where((Expense e) => e.id == expenseId)
        .cast<Expense?>()
        .firstWhere((Expense? e) => true, orElse: () => null);
    if (found != null) return found;
    throw StateError('Expense not found: $expenseId');
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
    final Map<String, dynamic> json = await _api.post<Map<String, dynamic>>(
      '/api/v1/trips/$tripId/expenses',
      body: <String, Object?>{
        'id': clientUuid,
        'userId': userId,
        'sourceId': sourceId,
        'categoryCode': categoryCode,
        'amount': <String, Object?>{
          'amount': amount.amountMinor,
          'currency': amount.currency,
        },
        'quantity': quantity,
        'details': details,
        'occurredAt': occurredAt.toIso8601String(),
        if (receiptObjectKey != null) 'receiptObjectKey': receiptObjectKey,
      },
    );
    return _parseExpense(json);
  }

  @override
  Future<Expense> update(String expenseId, ExpensePatch patch) async {
    final Map<String, Object?> body = <String, Object?>{};
    if (patch.sourceId != null) body['sourceId'] = patch.sourceId;
    if (patch.categoryCode != null) body['categoryCode'] = patch.categoryCode;
    if (patch.amount != null) {
      body['amount'] = <String, Object?>{
        'amount': patch.amount!.amountMinor,
        'currency': patch.amount!.currency,
      };
    }
    if (patch.details != null) body['details'] = patch.details;
    if (patch.occurredAt != null) {
      body['occurredAt'] = patch.occurredAt!.toIso8601String();
    }
    final Map<String, dynamic> json =
        await _api.patch<Map<String, dynamic>>('/api/v1/expenses/$expenseId', body: body);
    return _parseExpense(json);
  }

  @override
  Future<Expense> reassignSource(String expenseId, String newSourceId) {
    return update(expenseId, ExpensePatch(sourceId: newSourceId));
  }

  @override
  Future<List<Expense>> bulkReassignSource(Map<String, String> idToSourceId) async {
    final List<Expense> updated = <Expense>[];
    for (final MapEntry<String, String> e in idToSourceId.entries) {
      updated.add(await reassignSource(e.key, e.value));
    }
    return updated;
  }

  @override
  Future<String> uploadReceipt(String expenseId, ReceiptUpload upload) {
    // Receipt upload to MinIO/S3 lands in a follow-up. Falling back to the
    // fake repo means the receipt lives only in the in-memory DemoStore.
    return _fake.uploadReceipt(expenseId, upload);
  }

  @override
  Future<List<ExpenseSummary>> summary({
    required String tripId,
    required ExpenseSummaryScope scope,
    required ExpenseGroupBy groupBy,
    String? userId,
  }) async {
    // Compute client-side from the server's list — keeps a single source of
    // truth without adding a dedicated /summary endpoint right now.
    final List<Expense> rows = await list(tripId: tripId, userId: userId);
    final Map<String, Money> bucket = <String, Money>{};
    final Map<String, String> label = <String, String>{};
    String currency = rows.isEmpty ? 'SAR' : rows.first.amount.currency;
    for (final Expense e in rows) {
      final String key = switch (groupBy) {
        ExpenseGroupBy.category => e.categoryCode,
        ExpenseGroupBy.source => e.sourceId,
        ExpenseGroupBy.member => e.userId,
      };
      bucket.update(
        key,
        (Money v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
      label[key] = key;
      currency = e.amount.currency;
    }
    return bucket.entries
        .map((MapEntry<String, Money> entry) => ExpenseSummary(
              groupKey: entry.key,
              label: label[entry.key] ?? entry.key,
              amount: entry.value,
            ))
        .toList(growable: false);
  }

  Expense _parseExpense(Map<String, dynamic> j) {
    final Map<String, dynamic> amt = j['amount'] as Map<String, dynamic>;
    return Expense(
      id: j['id'] as String,
      tripId: j['tripId'] as String,
      userId: j['userId'] as String,
      sourceId: j['sourceId'] as String,
      categoryCode: j['categoryCode'] as String,
      amount: Money((amt['amount'] as num).toInt(), amt['currency'] as String),
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      details: (j['details'] as String?) ?? '',
      occurredAt: DateTime.parse(j['occurredAt'] as String),
      createdAt: DateTime.parse(
        (j['createdAt'] as String?) ?? j['occurredAt'] as String,
      ),
      receiptObjectKey: j['receiptObjectKey'] as String?,
    );
  }
}
