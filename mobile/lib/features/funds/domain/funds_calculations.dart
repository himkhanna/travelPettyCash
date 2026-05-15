import '../../../core/money/money.dart';
import 'funding.dart';

/// Leader's remaining-to-allocate budget per source: accepted admin-pool
/// inflow MINUS allocations the leader has committed (pending + accepted)
/// MINUS the leader's own committed expenses. Pending allocations count so
/// the Leader can't double-spend while a member's response is in flight.
///
/// Pure function — both fake and API impls call it with whatever allocation
/// + expense data their respective backends produce. Lives in `domain/` so
/// it has no IO dependencies.
Map<String, Money> computeLeaderAvailableBySource({
  required List<Allocation> allocations,
  required String leaderId,
  required String currency,
  required List<({String sourceId, Money amount})> leaderExpenses,
}) {
  final Map<String, Money> totals = <String, Money>{};

  for (final Allocation a in allocations) {
    if (a.status != AllocationStatus.accepted) continue;
    if (a.fromUserId == null && a.toUserId == leaderId) {
      totals.update(
        a.sourceId,
        (Money v) => v + a.amount,
        ifAbsent: () => a.amount,
      );
    }
  }
  for (final Allocation a in allocations) {
    if (a.fromUserId != leaderId) continue;
    if (a.status == AllocationStatus.declined) continue;
    totals.update(
      a.sourceId,
      (Money v) => v - a.amount,
      ifAbsent: () => -a.amount,
    );
  }
  for (final ({String sourceId, Money amount}) e in leaderExpenses) {
    totals.update(
      e.sourceId,
      (Money v) => v - e.amount,
      ifAbsent: () => -e.amount,
    );
  }
  return totals;
}
