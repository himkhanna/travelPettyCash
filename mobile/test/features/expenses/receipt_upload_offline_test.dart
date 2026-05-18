import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/core/sync/sync_coordinator.dart';
import 'package:pdd_petty_cash/features/expenses/application/expenses_providers.dart';
import 'package:pdd_petty_cash/features/expenses/application/pending_receipt_uploads.dart';
import 'package:pdd_petty_cash/features/expenses/data/expense_repository.dart';
import 'package:pdd_petty_cash/features/expenses/data/fake_expense_repository.dart';
import 'package:pdd_petty_cash/features/expenses/domain/expense.dart';

/// Slice 3C offline path:
///   1. Device is offline; user creates an expense with a receipt.
///   2. Expense is queued, receipt bytes are queued.
///   3. Device flips back online — SyncCoordinator drains pending
///      expenses, then runs the after-drain hook which drains the receipt
///      uploads.
void main() {
  group('Receipt upload offline path', () {
    late DemoStore store;
    late FakeConfig cfg;
    late FakeExpenseRepository repo;
    late ProviderContainer container;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      store = DemoStore.instance;
      store.resetForTest();
      store.markLoadedForTest();
      cfg = FakeConfig.instance
        ..setLatency(const Duration(milliseconds: 1))
        ..setFailureRate(0)
        ..setOfflineMode(value: false);
      repo = FakeExpenseRepository(store, cfg);
      container = ProviderContainer(
        overrides: <Override>[
          expenseRepositoryProvider.overrideWithValue(repo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('offline expense submission queues both the expense and the receipt',
        () async {
      cfg.setOfflineMode(value: true);
      // 1. Create an expense offline.
      final Expense pending = await repo.create(
        clientUuid: 'e-offline',
        tripId: 't1',
        userId: 'u1',
        sourceId: 'src-1',
        categoryCode: 'FOOD',
        amount: const Money(2500, 'SAR'),
        details: 'breakfast',
        occurredAt: DateTime(2026, 5, 18),
        idempotencyKey: 'idem-1',
      );
      expect(pending.pendingSync, true);
      expect(store.pendingExpenses.single.id, 'e-offline');

      // 2. Queue the receipt bytes (mimics what AddExpenseScreen does
      //    when FakeConfig.offlineMode is true).
      final PendingReceiptUploads q = container.read(
        pendingReceiptUploadsProvider,
      );
      q.enqueue(
        PendingReceiptUpload(
          expenseId: 'e-offline',
          bytes: Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xe0]),
          filename: 'breakfast.jpg',
        ),
      );
      expect(q.length, 1);
      expect(container.read(pendingReceiptExpenseIdsProvider),
          contains('e-offline'));

      // 3. Flip back online and drive a manual drain — SyncCoordinator
      //    will hit the after-drain hook which empties the receipt queue.
      cfg.setOfflineMode(value: false);
      final SyncCoordinator coordinator = SyncCoordinator(
        store,
        cfg,
        onAfterExpenseDrain: () => drainPendingReceiptUploads(container.read),
      );
      try {
        await coordinator.drain();
      } finally {
        coordinator.dispose();
      }

      // Expense moved out of pendingExpenses…
      expect(store.pendingExpenses, isEmpty);
      expect(store.expenses.single.id, 'e-offline');
      // …and the receipt queue is empty, with bytes now persisted under
      // the receipt store and pointed to by the expense.
      expect(q.length, 0);
      final String? key = store.expenses.single.receiptObjectKey;
      expect(key, isNotNull);
      expect(store.receiptBytes[key], isNotNull);
    });
  });
}
