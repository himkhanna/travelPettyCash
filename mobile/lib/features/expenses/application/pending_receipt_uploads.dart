import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/expense_repository.dart';
import 'expenses_providers.dart';

/// A single queued receipt upload, waiting either for the parent expense to
/// sync (offline path) or for a transient failure to clear (retry path).
@immutable
class PendingReceiptUpload {
  const PendingReceiptUpload({
    required this.expenseId,
    required this.bytes,
    required this.filename,
  });

  final String expenseId;
  final Uint8List bytes;
  final String filename;
}

/// In-memory queue of receipt uploads awaiting sync. Drained by
/// [SyncCoordinator] (slice 3C wires the drain after expense sync).
///
/// The store is reset across role changes the same way DemoStore is reset,
/// so the queue does not survive a re-launch in production — that would
/// require Drift persistence which lives in Phase 3 ops.
class PendingReceiptUploads extends ChangeNotifier {
  PendingReceiptUploads();

  final List<PendingReceiptUpload> _items = <PendingReceiptUpload>[];

  List<PendingReceiptUpload> get items =>
      List<PendingReceiptUpload>.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  int get length => _items.length;

  bool containsExpense(String expenseId) =>
      _items.any((PendingReceiptUpload u) => u.expenseId == expenseId);

  void enqueue(PendingReceiptUpload upload) {
    _items.add(upload);
    notifyListeners();
  }

  /// Remove the first queued upload for [expenseId]. Returns null if none
  /// match — callers should treat that as a no-op success.
  PendingReceiptUpload? takeFor(String expenseId) {
    final int idx =
        _items.indexWhere((PendingReceiptUpload u) => u.expenseId == expenseId);
    if (idx < 0) return null;
    final PendingReceiptUpload taken = _items.removeAt(idx);
    notifyListeners();
    return taken;
  }

  /// Drain every queued upload, calling [uploader] per item. Failures stop
  /// the drain so the user can retry — but the queue keeps its order.
  Future<void> drain(
    Future<void> Function(PendingReceiptUpload) uploader,
  ) async {
    while (_items.isNotEmpty) {
      final PendingReceiptUpload head = _items.first;
      await uploader(head);
      // uploader threw → never reaches here; we leave head in place.
      _items.removeAt(0);
      notifyListeners();
    }
  }
}

final Provider<PendingReceiptUploads> pendingReceiptUploadsProvider =
    Provider<PendingReceiptUploads>((Ref ref) {
  final PendingReceiptUploads q = PendingReceiptUploads();
  ref.onDispose(q.dispose);
  return q;
});

/// Reactive snapshot of the queue — rebuilds dependents whenever the
/// underlying ChangeNotifier fires. Use this from widgets that want to
/// render "pending upload" chips.
final Provider<Set<String>> pendingReceiptExpenseIdsProvider =
    Provider<Set<String>>((Ref ref) {
  final PendingReceiptUploads q = ref.watch(pendingReceiptUploadsProvider);
  void rebuild() => ref.invalidateSelf();
  q.addListener(rebuild);
  ref.onDispose(() => q.removeListener(rebuild));
  return q.items.map((PendingReceiptUpload u) => u.expenseId).toSet();
});

/// Helper that the [SyncCoordinator] calls once the expense sync drains —
/// best-effort upload of every queued receipt. Failures stop the drain so
/// the next call can retry; the queue keeps its order.
///
/// Accepts either a Riverpod [Ref] (production wiring) or a raw
/// [ProviderContainer.read]-style reader (tests). The reader signature is
/// `T Function<T>(ProviderListenable<T>)` so both shapes work.
Future<void> drainPendingReceiptUploads(
  T Function<T>(ProviderListenable<T>) read,
) async {
  final PendingReceiptUploads q = read(pendingReceiptUploadsProvider);
  final ExpenseRepository repo = read(expenseRepositoryProvider);
  await q.drain((PendingReceiptUpload u) async {
    await repo.uploadReceiptBytes(u.expenseId, u.bytes, u.filename);
  });
}
