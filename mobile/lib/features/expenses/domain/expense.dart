import '../../../core/money/money.dart';

/// Domain Expense — matches CLAUDE.md §5 Expense entity.
/// Source assignment can change after creation (audited event).
class Expense {
  const Expense({
    required this.id,
    required this.tripId,
    required this.userId,
    required this.sourceId,
    required this.categoryCode,
    required this.amount,
    required this.quantity,
    required this.details,
    required this.occurredAt,
    required this.createdAt,
    this.receiptObjectKey,
    this.vendor,
    this.updatedAt,
    this.deletedAt,
    this.pendingSync = false,
  });

  final String id;
  final String tripId;
  final String userId;
  final String sourceId;
  final String categoryCode;
  final Money amount;
  final int quantity;
  final String details;
  final DateTime occurredAt;
  final DateTime createdAt;
  final String? receiptObjectKey;

  /// Merchant / vendor name as scanned from the receipt or entered manually.
  /// Optional — older expenses won't have one. Surfaced as a small caption
  /// under the amount on the expense detail screen.
  final String? vendor;

  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// Client-side flag: this expense lives in the local Drift queue and has not
  /// yet been accepted by the server. Drives the "Pending sync" chip in UI.
  final bool pendingSync;

  Expense copyWith({
    String? id,
    String? tripId,
    String? userId,
    String? sourceId,
    String? categoryCode,
    Money? amount,
    int? quantity,
    String? details,
    DateTime? occurredAt,
    DateTime? createdAt,
    String? receiptObjectKey,
    String? vendor,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool? pendingSync,
  }) {
    return Expense(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      userId: userId ?? this.userId,
      sourceId: sourceId ?? this.sourceId,
      categoryCode: categoryCode ?? this.categoryCode,
      amount: amount ?? this.amount,
      quantity: quantity ?? this.quantity,
      details: details ?? this.details,
      occurredAt: occurredAt ?? this.occurredAt,
      createdAt: createdAt ?? this.createdAt,
      receiptObjectKey: receiptObjectKey ?? this.receiptObjectKey,
      vendor: vendor ?? this.vendor,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }
}

/// A single page of expenses with an optional cursor for the next page.
///
/// Cursor pagination contract (mirrors backend `GET /trips/{id}/expenses`):
/// `nextCursor == null` means the caller has reached the end of the feed.
/// Items are already sorted server-side (`occurredAt DESC, id DESC`).
class ExpensePage {
  const ExpensePage({required this.items, required this.nextCursor});

  final List<Expense> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

class ExpenseCategory {
  const ExpenseCategory({
    required this.code,
    required this.nameEn,
    required this.nameAr,
    required this.iconKey,
    required this.isActive,
  });

  final String code;
  final String nameEn;
  final String nameAr;
  final String iconKey;
  final bool isActive;
}

class ExpenseSummary {
  const ExpenseSummary({
    required this.groupKey,
    required this.label,
    required this.amount,
  });
  final String groupKey;
  final String label;
  final Money amount;
}

class ExpenseFilter {
  const ExpenseFilter({
    this.categoryCodes,
    this.sourceIds,
    this.memberIds,
    this.from,
    this.to,
  });

  final List<String>? categoryCodes;
  final List<String>? sourceIds;
  final List<String>? memberIds;
  final DateTime? from;
  final DateTime? to;
}
