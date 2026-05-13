import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/core/sync/sync_coordinator.dart';
import 'package:pdd_petty_cash/features/expenses/domain/expense.dart';

void main() {
  group('SyncCoordinator', () {
    late DemoStore store;
    late FakeConfig cfg;
    late SyncCoordinator coordinator;

    setUp(() {
      // Use a fresh isolated store per test by clearing the singleton.
      store = DemoStore.instance;
      store.expenses.clear();
      store.pendingExpenses.clear();
      cfg = FakeConfig.instance
        ..setLatency(const Duration(milliseconds: 1))
        ..setOfflineMode(value: false);
      coordinator = SyncCoordinator(store, cfg);
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('drain moves pending into accepted', () async {
      store.pendingExpenses.addAll(<Expense>[
        _exp('p1'),
        _exp('p2'),
      ]);
      await coordinator.drain();
      expect(store.pendingExpenses, isEmpty);
      expect(store.expenses.map((Expense e) => e.id), <String>['p1', 'p2']);
      expect(store.expenses.every((Expense e) => !e.pendingSync), true);
    });

    test('drain is a no-op when queue is empty', () async {
      await coordinator.drain();
      expect(coordinator.isSyncing, false);
    });

    test('pendingCount does not double-count during drain', () async {
      store.pendingExpenses.addAll(<Expense>[_exp('p1'), _exp('p2'), _exp('p3')]);
      expect(coordinator.pendingCount, 3);
      final Future<void> drainFuture = coordinator.drain();
      // Mid-drain — count should equal the in-flight queue, not the sum.
      expect(coordinator.pendingCount, lessThanOrEqualTo(3));
      await drainFuture;
      expect(coordinator.pendingCount, 0);
    });

    test('offline→online flip auto-drains', () async {
      cfg.setOfflineMode(value: true);
      store.pendingExpenses.add(_exp('p1'));
      cfg.setOfflineMode(value: false);
      // Give the coordinator a moment to drain.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.pendingExpenses, isEmpty);
      expect(store.expenses.single.id, 'p1');
    });
  });
}

Expense _exp(String id) => Expense(
      id: id,
      tripId: 'trip-1',
      userId: 'u-1',
      sourceId: 'src-1',
      categoryCode: 'FOOD',
      amount: const Money(1000, 'SAR'),
      quantity: 1,
      details: 'test',
      occurredAt: DateTime(2026, 5, 13),
      createdAt: DateTime(2026, 5, 13),
      pendingSync: true,
    );
