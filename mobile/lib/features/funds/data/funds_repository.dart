import '../../../core/money/money.dart';
import '../domain/funding.dart';

abstract class SourceRepository {
  Future<List<Source>> all();
}

abstract class AllocationRepository {
  Future<List<Allocation>> forTrip(String tripId, {String? memberId});

  /// Bulk create — used by Leader allocation flow (screen-inventory #18/#19).
  Future<List<Allocation>> createMany({
    required String tripId,
    required List<AllocationDraftRow> rows,
    required String idempotencyKey,
  });

  Future<Allocation> respond({
    required String allocationId,
    required AllocationStatus response,
  });
}

abstract class TransferRepository {
  Future<List<Transfer>> forTrip(String tripId);

  Future<Transfer> create({
    required String clientUuid,
    required String tripId,
    required String fromUserId,
    required String toUserId,
    required String sourceId,
    required Money amount,
    String? note,
    required String idempotencyKey,
  });

  Future<Transfer> respond({
    required String transferId,
    required AllocationStatus response,
  });
}
