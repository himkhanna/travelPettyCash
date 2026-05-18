import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/features/expenses/application/expense_paging_controller.dart';
import 'package:pdd_petty_cash/features/expenses/data/expense_repository.dart';
import 'package:pdd_petty_cash/features/expenses/data/fake_expense_repository.dart';
import 'package:pdd_petty_cash/features/expenses/domain/expense.dart';

/// Slice 3A — cursor pagination over the expense feed.
///
/// We seed the store with 30 expenses and exercise the controller state
/// machine directly. The end-to-end scroll integration is covered by the
/// broader integration_test/ suite; here we want fast, deterministic
/// checks on cursor consumption + loadMore + refresh.
void main() {
  group('ExpensePagingController', () {
    late DemoStore store;
    late FakeConfig cfg;
    late FakeExpenseRepository repo;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      store = DemoStore.instance;
      store.resetForTest();
      store.markLoadedForTest();
      cfg = FakeConfig.instance
        ..setLatency(Duration.zero)
        ..setFailureRate(0)
        ..setOfflineMode(value: false);
      repo = FakeExpenseRepository(store, cfg);
      _seed(store, count: 30);
    });

    test('first page returns 20 items with a next cursor', () async {
      final ExpensePagingController c = ExpensePagingController(
        repo: repo,
        tripId: 't1',
        scope: ExpenseSummaryScope.mine,
        userId: 'u1',
      );
      // Pump to let the eager first-page fetch complete.
      await pumpEventQueue();
      expect(c.state.items.length, 20);
      expect(c.state.hasMore, true);
      expect(c.state.loading, false);
    });

    test(
      'loadMore appends the next page and clears the cursor at the end',
      () async {
        final ExpensePagingController c = ExpensePagingController(
          repo: repo,
          tripId: 't1',
          scope: ExpenseSummaryScope.mine,
          userId: 'u1',
        );
        await pumpEventQueue();
        await c.loadMore();
        expect(c.state.items.length, 30);
        expect(
          c.state.hasMore,
          false,
          reason: 'After consuming all 30 expenses the cursor is null',
        );
        expect(c.state.loadingMore, false);
      },
    );

    test('loadMore is a no-op once the cursor is null', () async {
      final ExpensePagingController c = ExpensePagingController(
        repo: repo,
        tripId: 't1',
        scope: ExpenseSummaryScope.mine,
        userId: 'u1',
      );
      await pumpEventQueue();
      await c.loadMore(); // exhausts the feed
      final int before = c.state.items.length;
      await c.loadMore();
      expect(c.state.items.length, before);
    });

    test('refresh resets to the first page', () async {
      final ExpensePagingController c = ExpensePagingController(
        repo: repo,
        tripId: 't1',
        scope: ExpenseSummaryScope.mine,
        userId: 'u1',
      );
      await pumpEventQueue();
      await c.loadMore();
      expect(c.state.items.length, 30);
      await c.refresh();
      expect(c.state.items.length, 20);
      expect(c.state.hasMore, true);
    });

    test('first page returned items are sorted newest-first', () async {
      final ExpensePagingController c = ExpensePagingController(
        repo: repo,
        tripId: 't1',
        scope: ExpenseSummaryScope.mine,
        userId: 'u1',
      );
      await pumpEventQueue();
      final List<DateTime> dates = c.state.items
          .map((Expense e) => e.occurredAt)
          .toList(growable: false);
      for (int i = 1; i < dates.length; i++) {
        expect(
          dates[i].isBefore(dates[i - 1]) || dates[i].isAtSameMomentAs(dates[i - 1]),
          true,
          reason: 'Items should be sorted occurredAt DESC',
        );
      }
    });
  });
}

void _seed(DemoStore store, {required int count}) {
  final DateTime base = DateTime(2026, 5, 1);
  for (int i = 0; i < count; i++) {
    store.expenses.add(
      Expense(
        id: 'e-${i.toString().padLeft(3, '0')}',
        tripId: 't1',
        userId: 'u1',
        sourceId: 'src-1',
        categoryCode: 'FOOD',
        amount: Money(1000 + i * 10, 'SAR'),
        quantity: 1,
        details: 'expense $i',
        // Strictly decreasing dates so the natural sort matches insert order
        // (newest first in the page).
        occurredAt: base.subtract(Duration(hours: i)),
        createdAt: base,
      ),
    );
  }
}
