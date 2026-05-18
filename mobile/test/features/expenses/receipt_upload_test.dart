import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_petty_cash/core/fake/demo_store.dart';
import 'package:pdd_petty_cash/core/fake/fake_config.dart';
import 'package:pdd_petty_cash/core/money/money.dart';
import 'package:pdd_petty_cash/features/expenses/data/fake_expense_repository.dart';
import 'package:pdd_petty_cash/features/expenses/domain/expense.dart';

/// Slice 3C — direct receipt upload through the new bytes-based API.
///
/// Verifies: (1) upload stores bytes and patches receiptObjectKey on the
/// expense, (2) [receiptUrl] returns a data: URL backed by those bytes, so
/// the viewer can render without a network round-trip in the demo.
void main() {
  group('FakeExpenseRepository.uploadReceiptBytes', () {
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

      store.expenses.add(
        Expense(
          id: 'e1',
          tripId: 't1',
          userId: 'u1',
          sourceId: 'src-1',
          categoryCode: 'FOOD',
          amount: const Money(1500, 'SAR'),
          quantity: 1,
          details: 'lunch',
          occurredAt: DateTime(2026, 5, 18),
          createdAt: DateTime(2026, 5, 18),
        ),
      );
    });

    test('upload stores bytes and patches the expense receipt key', () async {
      final Uint8List bytes = Uint8List.fromList(<int>[
        // JPEG magic bytes so the mime sniffer agrees.
        0xff, 0xd8, 0xff, 0xe0,
        0x01, 0x02, 0x03,
      ]);
      final String key = await repo.uploadReceiptBytes(
        'e1',
        bytes,
        'lunch.jpg',
      );

      expect(key, isNotEmpty);
      expect(store.receiptBytes[key], bytes);
      expect(store.receiptMime[key], 'image/jpeg');
      expect(store.expenses.single.receiptObjectKey, key);
    });

    test('receiptUrl returns a base64 data: URL the viewer can render',
        () async {
      final Uint8List bytes = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4e, 0x47, // PNG magic
        0x0d, 0x0a, 0x1a, 0x0a,
      ]);
      await repo.uploadReceiptBytes('e1', bytes, 'lunch.png');
      final String? url = await repo.receiptUrl('e1');
      expect(url, isNotNull);
      expect(url!.startsWith('data:image/png;base64,'), true);
    });

    test('receiptUrl returns null for an expense without a receipt',
        () async {
      final String? url = await repo.receiptUrl('e1');
      expect(url, isNull);
    });
  });
}
