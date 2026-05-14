import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../../core/money/money.dart';
import '../../expenses/domain/expense.dart';
import '../../funds/domain/funding.dart';
import '../domain/trip.dart';
import 'trip_repository.dart';

/// Reads from DemoStore. Balance computation is **derived from the event
/// log** (allocations + transfers + expenses) — never cached, per CLAUDE.md §6.4.
class FakeTripRepository implements TripRepository {
  FakeTripRepository(
    this._store,
    this._cfg, {
    required String Function() currentUserId,
  }) : _currentUserId = currentUserId;

  final DemoStore _store;
  final FakeConfig _cfg;
  final String Function() _currentUserId;

  @override
  Future<List<Trip>> activeTrips() async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    final String me = _currentUserId();
    return _store.trips
        .where(
          (Trip t) =>
              t.status == TripStatus.active &&
              (t.memberIds.contains(me) || t.leaderId == me || _isAdmin()),
        )
        .toList(growable: false);
  }

  @override
  Future<List<Trip>> allTrips({TripStatus? status}) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    final String me = _currentUserId();
    return _store.trips
        .where((Trip t) {
          if (status != null && t.status != status) return false;
          return t.memberIds.contains(me) || t.leaderId == me || _isAdmin();
        })
        .toList(growable: false);
  }

  @override
  Future<Trip> tripById(String id) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    return _store.tripById(id);
  }

  @override
  Future<TripBalances> balances(String tripId, BalanceScope scope) async {
    await _store.ensureLoaded();
    await _cfg.waitLatency();
    final Trip trip = _store.tripById(tripId);
    final String me = _currentUserId();

    final List<Source> sources = _store.sources;
    final List<SourceBalance> perSource = sources
        .map((Source s) {
          final Money received = _sumReceived(
            tripId: tripId,
            sourceId: s.id,
            currency: trip.currency,
            scope: scope,
            me: me,
            leaderId: trip.leaderId,
          );
          final Money spent = _sumSpent(
            tripId: tripId,
            sourceId: s.id,
            currency: trip.currency,
            scope: scope,
            me: me,
          );
          return SourceBalance(
            sourceId: s.id,
            sourceName: s.name,
            sourceNameAr: s.nameAr,
            received: received,
            spent: spent,
            balance: received - spent,
          );
        })
        .toList(growable: false);

    Money fold(Money Function(SourceBalance) get) => perSource.fold(
      Money.zero(trip.currency),
      (Money a, SourceBalance b) => a + get(b),
    );

    return TripBalances(
      tripId: tripId,
      scope: scope,
      totalBudget: trip.totalBudget,
      totalSpent: fold((SourceBalance b) => b.spent),
      totalBalance: fold((SourceBalance b) => b.balance),
      perSource: perSource,
    );
  }

  Money _sumReceived({
    required String tripId,
    required String sourceId,
    required String currency,
    required BalanceScope scope,
    required String me,
    required String leaderId,
  }) {
    Money total = Money.zero(currency);
    for (final Allocation a in _store.allocations) {
      if (a.tripId != tripId || a.sourceId != sourceId) continue;
      if (a.status != AllocationStatus.accepted) continue;
      final bool include;
      switch (scope) {
        case BalanceScope.me:
          include = a.toUserId == me;
          break;
        case BalanceScope.leader:
          // Leader's inflow = allocations to the leader from Admin pool.
          include = a.toUserId == leaderId && a.fromUserId == null;
          break;
        case BalanceScope.trip:
          // Trip-wide rollup counts only the original inflow from the source
          // pool (fromUserId == null) to avoid double-counting redistributions
          // between Leader → Member.
          include = a.fromUserId == null;
          break;
      }
      if (include) total += a.amount;
    }

    // Accepted peer-to-peer transfers ADD to the recipient's "received".
    // Pending transfers don't count — the recipient sees a pending row in
    // the notifications screen and has to accept first.
    if (scope == BalanceScope.me) {
      for (final Transfer t in _store.transfers) {
        if (t.tripId != tripId || t.sourceId != sourceId) continue;
        if (t.status != AllocationStatus.accepted) continue;
        if (t.toUserId == me) total += t.amount;
      }
    }
    return total;
  }

  Money _sumSpent({
    required String tripId,
    required String sourceId,
    required String currency,
    required BalanceScope scope,
    required String me,
  }) {
    Money total = Money.zero(currency);
    for (final Expense exp in _store.expenses) {
      if (exp.tripId != tripId || exp.sourceId != sourceId) continue;
      if (exp.deletedAt != null) continue;
      final bool include;
      switch (scope) {
        case BalanceScope.me:
          include = exp.userId == me;
          break;
        case BalanceScope.leader:
        case BalanceScope.trip:
          include = true;
          break;
      }
      if (include) total += exp.amount;
    }

    // Money leaving the user via a peer transfer counts as outflow against
    // their balance — even though it's not literally a purchase, the wallet
    // shrinks. At trip scope this is internal redistribution and is ignored.
    if (scope == BalanceScope.me) {
      for (final Transfer t in _store.transfers) {
        if (t.tripId != tripId || t.sourceId != sourceId) continue;
        if (t.status != AllocationStatus.accepted) continue;
        if (t.fromUserId == me) total += t.amount;
      }
    }
    return total;
  }

  bool _isAdmin() {
    final FakeRole r = _cfg.role;
    return r == FakeRole.admin || r == FakeRole.superAdmin;
  }

  @override
  Future<Trip> createTrip({
    required String name,
    required String countryCode,
    required String currency,
    required String leaderId,
    required List<String> memberIds,
  }) {
    throw UnimplementedError('Admin createTrip lands in Milestone D');
  }

  @override
  Future<Trip> closeTrip(String tripId) {
    throw UnimplementedError('Admin closeTrip lands in Milestone D');
  }
}
