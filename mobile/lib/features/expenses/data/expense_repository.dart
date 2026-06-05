import 'dart:typed_data';

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

  /// Admin-only: list every non-deleted expense without an attached
  /// receipt. Backs the dashboard's "Receipt triage" surface.
  Future<List<Expense>> missingReceipts();

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
    // ADR-003: foreign-currency original (all-three-or-none; null = entered
    // directly in the trip currency). `amount` is always the trip-ccy base.
    String? originalCurrency,
    int? originalAmountMinor,
    double? exchangeRate,
  });

  Future<Expense> update(String expenseId, ExpensePatch patch);

  /// Source reassignment is its own audited event (CLAUDE.md §5).
  Future<Expense> reassignSource(String expenseId, String newSourceId);

  /// Bulk source reassignment — the "tick-box view" from screen-inventory #25.
  Future<List<Expense>> bulkReassignSource(Map<String, String> idToSourceId);

  Future<String> uploadReceipt(String expenseId, ReceiptUpload upload);

  /// Presigned URL for fetching the receipt directly from object storage.
  /// In API mode this is a short-lived MinIO link; in fake mode it returns
  /// a `data:` URL or the original file:// path.
  Future<String> receiptUrl(String expenseId);

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
    this.bytes,
    this.filename,
  });

  /// Local filesystem path. On Flutter Web this is a `blob:` URL — opaque
  /// to dart:io and unusable with `MultipartFile.fromFile`. Use [bytes]
  /// instead in that case.
  final String localPath;
  final String mime;
  final String sha256;
  final int byteSize;

  /// In-memory bytes for the receipt. Required on Flutter Web where
  /// [localPath] is a blob URL; optional on native where the file can be
  /// read from disk by path. When set, the API repository should prefer
  /// this over [localPath].
  final Uint8List? bytes;

  /// Display name for the multipart part. Defaults to the basename of
  /// [localPath] when not provided.
  final String? filename;
}
