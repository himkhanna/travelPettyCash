import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../../core/money/money.dart';
import '../domain/expense.dart';
import 'expense_repository.dart';

class FakeExpenseRepository implements ExpenseRepository {
  FakeExpenseRepository(this._store, this._cfg);

  final DemoStore _store;
  final FakeConfig _cfg;

  @override
  Future<List<Expense>> list({
    required String tripId,
    String? userId,
    ExpenseFilter? filter,
    String? cursor,
    int limit = 20,
  }) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();

    bool keep(Expense e) {
      if (e.tripId != tripId) return false;
      if (e.deletedAt != null) return false;
      if (userId != null && e.userId != userId) return false;
      if (filter != null) {
        if (filter.categoryCodes != null &&
            !filter.categoryCodes!.contains(e.categoryCode)) {
          return false;
        }
        if (filter.sourceIds != null &&
            !filter.sourceIds!.contains(e.sourceId)) {
          return false;
        }
        if (filter.memberIds != null && !filter.memberIds!.contains(e.userId)) {
          return false;
        }
        if (filter.from != null && e.occurredAt.isBefore(filter.from!)) {
          return false;
        }
        if (filter.to != null && e.occurredAt.isAfter(filter.to!)) {
          return false;
        }
      }
      return true;
    }

    final List<Expense> filtered = <Expense>[
      ..._store.pendingExpenses.where(keep),
      ..._store.expenses.where(keep),
    ]..sort((Expense a, Expense b) => b.occurredAt.compareTo(a.occurredAt));

    return filtered.take(limit).toList(growable: false);
  }

  @override
  Future<Expense> byId(String expenseId) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    return _store.expenses.firstWhere(
      (Expense e) => e.id == expenseId,
      orElse: () => throw StateError('Expense not found: $expenseId'),
    );
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
    await _store.ensureLoaded();

    // Idempotency: if a row already exists with this id (in pending OR
    // accepted), return it. CLAUDE.md §11 — client UUID is canonical.
    final int existing = _store.expenses.indexWhere(
      (Expense e) => e.id == clientUuid,
    );
    if (existing >= 0) return _store.expenses[existing];
    final int existingPending = _store.pendingExpenses.indexWhere(
      (Expense e) => e.id == clientUuid,
    );
    if (existingPending >= 0) return _store.pendingExpenses[existingPending];

    if (_cfg.offlineMode) {
      // Queue locally. Skip latency + failure injection — the device isn't
      // talking to anyone. SyncCoordinator handles the eventual upload.
      final Expense pending = Expense(
        id: clientUuid,
        tripId: tripId,
        userId: userId,
        sourceId: sourceId,
        categoryCode: categoryCode,
        amount: amount,
        quantity: quantity,
        details: details,
        occurredAt: occurredAt,
        createdAt: _cfg.now(),
        receiptObjectKey: receiptObjectKey,
        pendingSync: true,
      );
      _store.pendingExpenses.add(pending);
      _store.emit(DemoStoreEvent.pendingExpensesChanged);
      return pending;
    }

    await _cfg.waitLatency();
    _cfg.maybeFail(op: 'expenses.create');

    final Expense e = Expense(
      id: clientUuid,
      tripId: tripId,
      userId: userId,
      sourceId: sourceId,
      categoryCode: categoryCode,
      amount: amount,
      quantity: quantity,
      details: details,
      occurredAt: occurredAt,
      createdAt: _cfg.now(),
      receiptObjectKey: receiptObjectKey,
    );
    _store.expenses.add(e);
    _store.emit(DemoStoreEvent.expensesChanged);
    return e;
  }

  @override
  Future<Expense> update(String expenseId, ExpensePatch patch) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    _cfg.maybeFail(op: 'expenses.update');
    final int i = _store.expenses.indexWhere((Expense e) => e.id == expenseId);
    if (i < 0) throw StateError('Expense not found: $expenseId');
    final Expense old = _store.expenses[i];
    final Expense updated = Expense(
      id: old.id,
      tripId: old.tripId,
      userId: old.userId,
      sourceId: patch.sourceId ?? old.sourceId,
      categoryCode: patch.categoryCode ?? old.categoryCode,
      amount: patch.amount ?? old.amount,
      quantity: old.quantity,
      details: patch.details ?? old.details,
      occurredAt: patch.occurredAt ?? old.occurredAt,
      createdAt: old.createdAt,
      receiptObjectKey: old.receiptObjectKey,
      updatedAt: _cfg.now(),
    );
    _store.expenses[i] = updated;
    _store.emit(DemoStoreEvent.expensesChanged);
    return updated;
  }

  @override
  Future<Expense> reassignSource(String expenseId, String newSourceId) =>
      update(expenseId, ExpensePatch(sourceId: newSourceId));

  @override
  Future<List<Expense>> bulkReassignSource(
    Map<String, String> idToSourceId,
  ) async {
    final List<Expense> out = <Expense>[];
    for (final MapEntry<String, String> e in idToSourceId.entries) {
      out.add(await reassignSource(e.key, e.value));
    }
    return out;
  }

  @override
  Future<String> uploadReceipt(String expenseId, ReceiptUpload upload) async {
    await _cfg.waitLatency();
    _cfg.maybeFail(op: 'expenses.uploadReceipt');
    final String objectKey = 'demo/receipts/${upload.sha256}.jpg';
    final int i = _store.expenses.indexWhere((Expense e) => e.id == expenseId);
    if (i >= 0) {
      final Expense old = _store.expenses[i];
      _store.expenses[i] = Expense(
        id: old.id,
        tripId: old.tripId,
        userId: old.userId,
        sourceId: old.sourceId,
        categoryCode: old.categoryCode,
        amount: old.amount,
        quantity: old.quantity,
        details: old.details,
        occurredAt: old.occurredAt,
        createdAt: old.createdAt,
        receiptObjectKey: objectKey,
        updatedAt: _cfg.now(),
      );
      _store.emit(DemoStoreEvent.expensesChanged);
    }
    return objectKey;
  }

  @override
  Future<List<ExpenseSummary>> summary({
    required String tripId,
    required ExpenseSummaryScope scope,
    required ExpenseGroupBy groupBy,
    String? userId,
  }) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();

    final Iterable<Expense> source = _store.expenses.where((Expense e) {
      if (e.tripId != tripId || e.deletedAt != null) return false;
      switch (scope) {
        case ExpenseSummaryScope.mine:
          return e.userId == userId;
        case ExpenseSummaryScope.user:
          return e.userId == userId;
        case ExpenseSummaryScope.all:
          return true;
      }
    });

    final Map<String, Money> totals = <String, Money>{};
    final Map<String, String> labels = <String, String>{};
    final String currency = _store.tripById(tripId).currency;

    for (final Expense e in source) {
      final String key;
      final String label;
      switch (groupBy) {
        case ExpenseGroupBy.category:
          key = e.categoryCode;
          label = _store.categoryByCode(e.categoryCode).nameEn;
          break;
        case ExpenseGroupBy.source:
          key = e.sourceId;
          label = _store.sourceById(e.sourceId).name;
          break;
        case ExpenseGroupBy.member:
          key = e.userId;
          label = _store.userById(e.userId).displayName;
          break;
      }
      totals[key] = (totals[key] ?? Money.zero(currency)) + e.amount;
      labels[key] = label;
    }

    return totals.entries
        .map(
          (MapEntry<String, Money> en) => ExpenseSummary(
            groupKey: en.key,
            label: labels[en.key]!,
            amount: en.value,
          ),
        )
        .toList(growable: false);
  }
}
