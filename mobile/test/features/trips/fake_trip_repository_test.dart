import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/features/expenses/domain/expense.dart';
import 'package:pdd_petty_cash/features/funds/domain/funding.dart';
import 'package:pdd_petty_cash/features/trips/data/fake_trip_repository.dart';
import 'package:pdd_petty_cash/features/trips/domain/trip.dart';

void main() {
  group('FakeTripRepository.balances — derived from event log (§6.4)', () {
    late DemoStore store;
    late FakeConfig cfg;
    late FakeTripRepository repo;

    setUp(() {
      store = DemoStore.instance;
      store.users.clear();
      store.sources
        ..clear()
        ..add(const Source(id: 'src-z', name: 'Zabeel', nameAr: 'زعبيل', isActive: true));
      store.trips
        ..clear()
        ..add(Trip(
          id: 't1',
          name: 'KSA',
          countryCode: 'SA',
          countryName: 'Saudi Arabia',
          currency: 'SAR',
          status: TripStatus.active,
          createdBy: 'u-admin',
          leaderId: 'u-leader',
          memberIds: const <String>['u-member'],
          totalBudget: const Money(1000000, 'SAR'),
          createdAt: DateTime(2026, 5, 1),
        ));
      store.allocations
        ..clear()
        ..addAll(<Allocation>[
          Allocation(
            id: 'a1',
            tripId: 't1',
            fromUserId: null,
            toUserId: 'u-leader',
            sourceId: 'src-z',
            amount: const Money(800000, 'SAR'),
            status: AllocationStatus.accepted,
            createdAt: DateTime(2026, 5, 1),
          ),
          Allocation(
            id: 'a2',
            tripId: 't1',
            fromUserId: 'u-leader',
            toUserId: 'u-member',
            sourceId: 'src-z',
            amount: const Money(200000, 'SAR'),
            status: AllocationStatus.accepted,
            createdAt: DateTime(2026, 5, 1),
          ),
        ]);
      store.expenses
        ..clear()
        ..add(Expense(
          id: 'e1',
          tripId: 't1',
          userId: 'u-member',
          sourceId: 'src-z',
          categoryCode: 'FOOD',
          amount: const Money(50000, 'SAR'),
          quantity: 1,
          details: 'lunch',
          occurredAt: DateTime(2026, 5, 2),
          createdAt: DateTime(2026, 5, 2),
        ));
      cfg = FakeConfig.instance..setLatency(Duration.zero);
      repo = FakeTripRepository(store, cfg, currentUserId: () => 'u-member');
    });

    test('me-scope balance = leader→member allocation minus their spend', () async {
      final TripBalances b = await repo.balances('t1', BalanceScope.me);
      expect(b.totalSpent, const Money(50000, 'SAR'));
      expect(b.totalBalance, const Money(150000, 'SAR'));
      expect(b.perSource.single.received, const Money(200000, 'SAR'));
      expect(b.perSource.single.spent, const Money(50000, 'SAR'));
    });

    test('trip-scope balance counts only admin→leader inflow once', () async {
      final TripBalances b = await repo.balances('t1', BalanceScope.trip);
      expect(b.perSource.single.received, const Money(800000, 'SAR'));
      expect(b.totalSpent, const Money(50000, 'SAR'));
    });

    test('pending allocations do not count toward balance', () async {
      store.allocations.add(Allocation(
        id: 'a3',
        tripId: 't1',
        fromUserId: 'u-leader',
        toUserId: 'u-member',
        sourceId: 'src-z',
        amount: const Money(99999, 'SAR'),
        status: AllocationStatus.pending,
        createdAt: DateTime(2026, 5, 3),
      ));
      final TripBalances b = await repo.balances('t1', BalanceScope.me);
      expect(b.perSource.single.received, const Money(200000, 'SAR'));
    });

    test('negative balance is permitted (CLAUDE.md §6.4)', () async {
      store.expenses.add(Expense(
        id: 'e2',
        tripId: 't1',
        userId: 'u-member',
        sourceId: 'src-z',
        categoryCode: 'FOOD',
        amount: const Money(300000, 'SAR'),
        quantity: 1,
        details: 'dinner',
        occurredAt: DateTime(2026, 5, 3),
        createdAt: DateTime(2026, 5, 3),
      ));
      final TripBalances b = await repo.balances('t1', BalanceScope.me);
      expect(b.totalBalance.isNegative, true);
    });
  });
}
