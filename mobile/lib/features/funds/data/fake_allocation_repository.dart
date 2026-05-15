import 'package:uuid/uuid.dart';

import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../../core/money/money.dart';
import '../../notifications/domain/notification.dart';
import '../domain/funding.dart';
import '../domain/funds_calculations.dart';
import 'funds_repository.dart';

class FakeAllocationRepository implements AllocationRepository {
  FakeAllocationRepository(this._store, this._cfg);

  final DemoStore _store;
  final FakeConfig _cfg;
  static const Uuid _uuid = Uuid();

  @override
  Future<List<Allocation>> forTrip(String tripId, {String? memberId}) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    return _store.allocations.where((Allocation a) {
      if (a.tripId != tripId) return false;
      if (memberId != null && a.toUserId != memberId) return false;
      return true;
    }).toList(growable: false);
  }

  @override
  Future<List<Allocation>> createMany({
    required String tripId,
    required List<AllocationDraftRow> rows,
    required String idempotencyKey,
  }) async {
    await _store.ensureLoaded();
    if (!_cfg.offlineMode) {
      await _cfg.waitLatency();
      _cfg.maybeFail(op: 'allocations.createMany');
    }
    final DateTime now = _cfg.now();
    final String fromUserId = _resolveFromUserId(tripId);

    final List<Allocation> created = <Allocation>[];
    for (final AllocationDraftRow r in rows) {
      if (r.amount.isZero) continue;
      final String allocId = 'alloc-${_uuid.v4().substring(0, 8)}';
      final Allocation a = Allocation(
        id: allocId,
        tripId: tripId,
        fromUserId: fromUserId,
        toUserId: r.toUserId,
        sourceId: r.sourceId,
        amount: r.amount,
        status: AllocationStatus.pending,
        createdAt: now,
      );
      _store.allocations.add(a);
      created.add(a);

      // Drop an ALLOCATION_RECEIVED actionable notification on the recipient.
      _store.notifications.add(
        AppNotification(
          id: 'notif-${allocId.substring(6)}',
          userId: r.toUserId,
          type: NotificationType.allocationReceived,
          payload: <String, Object?>{
            'allocationId': allocId,
            'fromUserId': fromUserId,
            'tripId': tripId,
            'sourceId': r.sourceId,
            'amountMinor': r.amount.amountMinor,
            'currency': r.amount.currencyCode,
          },
          actionable: true,
          state: NotificationState.unread,
          createdAt: now,
        ),
      );
    }

    _store.emit(DemoStoreEvent.allocationsChanged);
    _store.emit(DemoStoreEvent.notificationsChanged);
    return created;
  }

  @override
  Future<Allocation> respond({
    required String allocationId,
    required AllocationStatus response,
  }) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    _cfg.maybeFail(op: 'allocations.respond');

    final int i = _store.allocations.indexWhere(
      (Allocation a) => a.id == allocationId,
    );
    if (i < 0) throw StateError('Allocation not found: $allocationId');
    final Allocation old = _store.allocations[i];
    final Allocation updated = Allocation(
      id: old.id,
      tripId: old.tripId,
      fromUserId: old.fromUserId,
      toUserId: old.toUserId,
      sourceId: old.sourceId,
      amount: old.amount,
      status: response,
      note: old.note,
      createdAt: old.createdAt,
      respondedAt: _cfg.now(),
    );
    _store.allocations[i] = updated;
    _store.emit(DemoStoreEvent.allocationsChanged);
    return updated;
  }

  /// Resolves who is "doing" the allocation. For Phase 1 demo, this is the
  /// trip's leader since only Leaders open the Allocate Funds screen.
  String _resolveFromUserId(String tripId) {
    final List<dynamic> trips = _store.trips;
    for (final dynamic t in trips) {
      if (t.id == tripId) return t.leaderId as String;
    }
    throw StateError('Trip not found: $tripId');
  }

  /// Wraps the shared {@link leaderAvailableBySource} computation in a way
  /// that taps the demo store for the leader's own expenses (the expense
  /// backend isn't wired yet). Kept on the fake repo so existing call sites
  /// don't have to know about the expense fetch.
  Map<String, Money> leaderAvailableBySource({
    required String tripId,
    required String leaderId,
    required String currency,
  }) {
    final List<Allocation> tripAllocs = _store.allocations
        .where((Allocation a) => a.tripId == tripId)
        .toList(growable: false);
    final List<({String sourceId, Money amount})> expenses = _store.expenses
        .where((dynamic e) =>
            e.tripId == tripId &&
            e.userId == leaderId &&
            e.deletedAt == null)
        .map<({String sourceId, Money amount})>((dynamic e) => (
              sourceId: e.sourceId as String,
              amount: e.amount as Money,
            ))
        .toList(growable: false);
    return computeLeaderAvailableBySource(
      allocations: tripAllocs,
      leaderId: leaderId,
      currency: currency,
      leaderExpenses: expenses,
    );
  }
}
