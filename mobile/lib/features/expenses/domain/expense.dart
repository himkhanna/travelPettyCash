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
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// Client-side flag: this expense lives in the local Drift queue and has not
  /// yet been accepted by the server. Drives the "Pending sync" chip in UI.
  final bool pendingSync;
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
