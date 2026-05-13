import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/expenses/domain/expense.dart';
import '../fake/demo_store.dart';
import '../fake/fake_config.dart';

/// Coordinates draining the offline queue when the device comes back online.
///
/// In the demo it watches FakeConfig.offlineMode; in production it would
/// listen to connectivity_plus events. The behaviour is the same either way:
/// drain pending_expenses one at a time with a short delay so the UI can
/// reflect progress.
class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator(this._store, this._cfg) {
    _cfg.addListener(_onConfigChange);
    _wasOffline = _cfg.offlineMode;
  }

  final DemoStore _store;
  final FakeConfig _cfg;

  bool _wasOffline = false;
  bool _syncing = false;
  int _remaining = 0;
  Object? _lastError;

  bool get isSyncing => _syncing;
  // During an active drain, `_remaining` mirrors the in-progress queue size;
  // when idle, fall back to the raw queue. Don't sum — that double-counts.
  int get pendingCount => _syncing ? _remaining : _store.pendingExpenses.length;
  int get remainingInCurrentBatch => _remaining;
  Object? get lastError => _lastError;

  void _onConfigChange() {
    final bool nowOffline = _cfg.offlineMode;
    if (_wasOffline && !nowOffline) {
      unawaited(drain());
    }
    _wasOffline = nowOffline;
    notifyListeners();
  }

  /// Triggered manually (pull-to-refresh) or automatically on offline→online.
  Future<void> drain() async {
    if (_syncing) return;
    if (_store.pendingExpenses.isEmpty) return;
    _syncing = true;
    _lastError = null;
    _remaining = _store.pendingExpenses.length;
    notifyListeners();

    try {
      while (_store.pendingExpenses.isNotEmpty) {
        final Expense pending = _store.pendingExpenses.first;
        // Simulate a per-item server round-trip.
        await Future<void>.delayed(_cfg.latency);
        final Expense accepted = Expense(
          id: pending.id,
          tripId: pending.tripId,
          userId: pending.userId,
          sourceId: pending.sourceId,
          categoryCode: pending.categoryCode,
          amount: pending.amount,
          quantity: pending.quantity,
          details: pending.details,
          occurredAt: pending.occurredAt,
          createdAt: pending.createdAt,
          receiptObjectKey: pending.receiptObjectKey,
        );
        _store.expenses.add(accepted);
        _store.pendingExpenses.removeAt(0);
        _remaining = _store.pendingExpenses.length;
        _store.emit(DemoStoreEvent.expensesChanged);
        _store.emit(DemoStoreEvent.pendingExpensesChanged);
        notifyListeners();
      }
    } catch (e) {
      _lastError = e;
    } finally {
      _syncing = false;
      _remaining = 0;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _cfg.removeListener(_onConfigChange);
    super.dispose();
  }
}

final Provider<SyncCoordinator> syncCoordinatorProvider =
    Provider<SyncCoordinator>((Ref ref) {
      final SyncCoordinator c = SyncCoordinator(
        ref.watch(demoStoreProvider),
        ref.watch(fakeConfigProvider),
      );
      ref.onDispose(c.dispose);
      return c;
    });

/// Watchable view of the coordinator for UI badges and banners.
final Provider<SyncState> syncStateProvider = Provider<SyncState>((Ref ref) {
  final SyncCoordinator c = ref.watch(syncCoordinatorProvider);
  // Bind the ChangeNotifier into Riverpod's rebuild loop.
  c.addListener(ref.invalidateSelf);
  ref.onDispose(() => c.removeListener(ref.invalidateSelf));
  return SyncState(
    isSyncing: c.isSyncing,
    pendingCount: c.pendingCount,
    lastError: c.lastError,
  );
});

class SyncState {
  const SyncState({
    required this.isSyncing,
    required this.pendingCount,
    required this.lastError,
  });
  final bool isSyncing;
  final int pendingCount;
  final Object? lastError;
}
