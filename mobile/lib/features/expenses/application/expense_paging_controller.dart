import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fake/demo_store.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../data/expense_repository.dart';
import '../domain/expense.dart';
import 'expenses_providers.dart';

/// Family key for [pagingControllerProvider]. Equality is by `(tripId,
/// scope)` so the screen rebuilds the same controller when it remounts.
@immutable
class ExpensePagingKey {
  const ExpensePagingKey({required this.tripId, required this.scope});

  final String tripId;
  final ExpenseSummaryScope scope;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpensePagingKey &&
          other.tripId == tripId &&
          other.scope == scope;

  @override
  int get hashCode => Object.hash(tripId, scope);

  @override
  String toString() => 'ExpensePagingKey(tripId=$tripId, scope=$scope)';
}

/// Immutable snapshot of the paging UI state.
///
/// `loading == true` while the first page is in flight; `loadingMore == true`
/// once the user has scrolled to trigger a follow-up fetch. `nextCursor ==
/// null && items.isNotEmpty` is the "no more results" terminal state — the
/// list footer shows the end-of-list label.
@immutable
class ExpensePagingState {
  const ExpensePagingState({
    required this.items,
    required this.nextCursor,
    required this.loading,
    required this.loadingMore,
    required this.error,
  });

  const ExpensePagingState.initial()
      : items = const <Expense>[],
        nextCursor = null,
        loading = true,
        loadingMore = false,
        error = null;

  final List<Expense> items;
  final String? nextCursor;
  final bool loading;
  final bool loadingMore;
  final Object? error;

  bool get hasMore => nextCursor != null;
  bool get isEmpty => items.isEmpty && !loading && error == null;

  ExpensePagingState copyWith({
    List<Expense>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return ExpensePagingState(
      items: items ?? this.items,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// StateNotifier that drives infinite-scroll expense feeds.
///
/// Lifecycle:
/// - constructor → [_loadFirst] runs eagerly so the first page is in flight
///   before the widget tree settles.
/// - [loadMore] is called from the scroll listener when the viewport is
///   within 200px of the bottom; it no-ops if [state.loadingMore] is already
///   true or there's no next cursor.
/// - [refresh] resets the cursor and reloads from the top (pull-to-refresh).
class ExpensePagingController extends StateNotifier<ExpensePagingState> {
  ExpensePagingController({
    required this.repo,
    required this.tripId,
    required this.scope,
    required this.userId,
    this.pageSize = 20,
  }) : super(const ExpensePagingState.initial()) {
    // Fire and forget; loading=true is already set by .initial().
    _loadFirst();
  }

  final ExpenseRepository repo;
  final String tripId;
  final ExpenseSummaryScope scope;
  final String? userId;
  final int pageSize;

  Future<void> _loadFirst() async {
    try {
      final ExpensePage page = await repo.pageForTrip(
        tripId: tripId,
        scope: scope,
        userId: userId,
        limit: pageSize,
      );
      if (!mounted) return;
      state = ExpensePagingState(
        items: page.items,
        nextCursor: page.nextCursor,
        loading: false,
        loadingMore: false,
        error: null,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  /// Pull-to-refresh handler. Drops the existing list and reloads page 1.
  Future<void> refresh() async {
    state = const ExpensePagingState.initial();
    await _loadFirst();
  }

  /// Triggered by the scroll listener once the viewport is near the bottom.
  /// Idempotent: a second call while a fetch is in flight is a no-op.
  Future<void> loadMore() async {
    if (state.loadingMore || state.loading) return;
    if (state.nextCursor == null) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final ExpensePage page = await repo.pageForTrip(
        tripId: tripId,
        scope: scope,
        userId: userId,
        cursor: state.nextCursor,
        limit: pageSize,
      );
      if (!mounted) return;
      state = ExpensePagingState(
        items: <Expense>[...state.items, ...page.items],
        nextCursor: page.nextCursor,
        loading: false,
        loadingMore: false,
        error: null,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loadingMore: false, error: e);
    }
  }
}

/// Family-keyed paging controller. Use [ExpensePagingKey] to scope state per
/// (trip, scope) tuple so My Expenses and Trip Expenses keep independent
/// cursors but the same identity survives a widget remount.
final StateNotifierProviderFamily<ExpensePagingController, ExpensePagingState,
        ExpensePagingKey> pagingControllerProvider =
    StateNotifierProvider.family<ExpensePagingController, ExpensePagingState,
        ExpensePagingKey>((Ref ref, ExpensePagingKey key) {
  final ExpenseRepository repo = ref.watch(expenseRepositoryProvider);
  final User? me = ref.watch(currentUserProvider).valueOrNull;
  // Re-create when the underlying expense store mutates so a new expense
  // surfaces at the top without requiring a manual pull-to-refresh.
  final StreamSubscription<DemoStoreEvent> sub =
      ref.watch(demoStoreProvider).events.listen((DemoStoreEvent e) {
    if (e == DemoStoreEvent.expensesChanged ||
        e == DemoStoreEvent.pendingExpensesChanged) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(sub.cancel);
  return ExpensePagingController(
    repo: repo,
    tripId: key.tripId,
    scope: key.scope,
    userId: me?.id,
  );
});
