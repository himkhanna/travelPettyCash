import '../../../core/money/money.dart';
import '../domain/expense.dart';

abstract class ExpenseRepository {
  Future<List<Expense>> list({
    required String tripId,
    String? userId,
    ExpenseFilter? filter,
    String? cursor,
    int limit = 20,
  });

  Future<Expense> byId(String expenseId);

  /// Client provides the id (UUID) — server accepts it as canonical
  /// (CLAUDE.md §11 offline rules).
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
  });

  Future<Expense> update(String expenseId, ExpensePatch patch);

  /// Source reassignment is its own audited event (CLAUDE.md §5).
  Future<Expense> reassignSource(String expenseId, String newSourceId);

  /// Bulk source reassignment — the "tick-box view" from screen-inventory #25.
  Future<List<Expense>> bulkReassignSource(Map<String, String> idToSourceId);

  Future<String> uploadReceipt(String expenseId, ReceiptUpload upload);

  Future<List<ExpenseSummary>> summary({
    required String tripId,
    required ExpenseSummaryScope scope,
    required ExpenseGroupBy groupBy,
    String? userId,
  });
}

class ExpensePatch {
  const ExpensePatch({
    this.sourceId,
    this.categoryCode,
    this.amount,
    this.details,
    this.occurredAt,
  });

  final String? sourceId;
  final String? categoryCode;
  final Money? amount;
  final String? details;
  final DateTime? occurredAt;
}

enum ExpenseSummaryScope { mine, all, user }

enum ExpenseGroupBy { category, source, member }

class ReceiptUpload {
  const ReceiptUpload({
    required this.localPath,
    required this.mime,
    required this.sha256,
    required this.byteSize,
  });

  final String localPath;
  final String mime;
  final String sha256;
  final int byteSize;
}
