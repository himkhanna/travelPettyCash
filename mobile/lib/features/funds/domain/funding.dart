import '../../../core/money/money.dart';

class Source {
  const Source({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.isActive,
  });
  final String id;
  final String name;
  final String nameAr;
  final bool isActive;
}

enum AllocationStatus { pending, accepted, declined }

class Allocation {
  const Allocation({
    required this.id,
    required this.tripId,
    required this.toUserId,
    required this.sourceId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.fromUserId,
    this.note,
    this.respondedAt,
  });

  final String id;
  final String tripId;
  final String? fromUserId; // null = Admin allocation from source pool
  final String toUserId;
  final String sourceId;
  final Money amount;
  final AllocationStatus status;
  final String? note;
  final DateTime createdAt;
  final DateTime? respondedAt;
}

class Transfer {
  const Transfer({
    required this.id,
    required this.tripId,
    required this.fromUserId,
    required this.toUserId,
    required this.sourceId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.note,
    this.respondedAt,
  });

  final String id;
  final String tripId;
  final String fromUserId;
  final String toUserId;
  final String sourceId;
  final Money amount;
  final AllocationStatus status;
  final String? note;
  final DateTime createdAt;
  final DateTime? respondedAt;
}

class AllocationDraftRow {
  const AllocationDraftRow({
    required this.toUserId,
    required this.sourceId,
    required this.amount,
  });
  final String toUserId;
  final String sourceId;
  final Money amount;
}
