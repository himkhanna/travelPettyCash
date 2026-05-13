import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/features/expenses/data/fake_expense_repository.dart';
import 'package:pdd_petty_cash/features/expenses/domain/expense.dart';

void main() {
  group('FakeExpenseRepository.create', () {
    late DemoStore store;
    late FakeConfig cfg;
    late FakeExpenseRepository repo;

    setUp(() {
      store = DemoStore.instance;
      store.expenses.clear();
      store.pendingExpenses.clear();
      cfg = FakeConfig.instance
        ..setLatency(Duration.zero)
        ..setFailureRate(0)
        ..setOfflineMode(value: false);
      repo = FakeExpenseRepository(store, cfg);
    });

    test('online create goes to accepted list', () async {
      final Expense e = await _create(repo, 'e1');
      expect(store.expenses.single.id, 'e1');
      expect(store.pendingExpenses, isEmpty);
      expect(e.pendingSync, false);
    });

    test(
      'offline create goes to pending queue with pendingSync=true',
      () async {
        cfg.setOfflineMode(value: true);
        final Expense e = await _create(repo, 'e1');
        expect(store.expenses, isEmpty);
        expect(store.pendingExpenses.single.id, 'e1');
        expect(e.pendingSync, true);
      },
    );

    test(
      'idempotency: replaying same client UUID returns existing row',
      () async {
        await _create(repo, 'e1');
        final Expense second = await _create(repo, 'e1');
        expect(second.id, 'e1');
        expect(store.expenses.length, 1);
      },
    );

    test('idempotency works across the offline→online boundary', () async {
      cfg.setOfflineMode(value: true);
      await _create(repo, 'e1');
      cfg.setOfflineMode(value: false);
      // Same client UUID submitted again should not create a duplicate.
      final Expense second = await _create(repo, 'e1');
      expect(second.id, 'e1');
      // pendingExpenses still has the original; SyncCoordinator (not under
      // test here) is responsible for moving it.
      expect(store.pendingExpenses.length + store.expenses.length, 1);
    });

    test('list merges pending expenses into the result', () async {
      cfg.setOfflineMode(value: true);
      await _create(repo, 'e1');
      cfg.setOfflineMode(value: false);
      await _create(repo, 'e2');

      final List<Expense> all = await repo.list(tripId: 't1', userId: 'u-1');
      expect(all.map((Expense e) => e.id).toSet(), <String>{'e1', 'e2'});
      expect(
        all.firstWhere((Expense e) => e.id == 'e1').pendingSync,
        true,
        reason: 'Pending expense surfaces via list()',
      );
    });
  });
}

Future<Expense> _create(FakeExpenseRepository repo, String id) {
  return repo.create(
    clientUuid: id,
    tripId: 't1',
    userId: 'u-1',
    sourceId: 'src-1',
    categoryCode: 'FOOD',
    amount: const Money(1000, 'SAR'),
    details: 'test',
    occurredAt: DateTime(2026, 5, 13),
    idempotencyKey: 'idem-$id',
  );
}
