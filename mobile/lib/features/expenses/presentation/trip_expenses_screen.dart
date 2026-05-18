import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/expense_paging_controller.dart';
import '../data/expense_repository.dart';
import '../domain/expense.dart';
import 'widgets/expense_filter_sheet.dart';

/// Screen-inventory #26 — Trip Expenses (all members) for Leader/Admin/SuperAdmin.
///
/// Slice 3A: cursor-paginated infinite scroll. See [pagingControllerProvider]
/// for the state machine.
class TripExpensesScreen extends ConsumerStatefulWidget {
  const TripExpensesScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<TripExpensesScreen> createState() =>
      _TripExpensesScreenState();
}

class _TripExpensesScreenState extends ConsumerState<TripExpensesScreen> {
  final ScrollController _scrollCtrl = ScrollController();

  ExpensePagingKey get _key =>
      ExpensePagingKey(tripId: widget.tripId, scope: ExpenseSummaryScope.all);

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final double remaining =
        _scrollCtrl.position.maxScrollExtent - _scrollCtrl.position.pixels;
    if (remaining < 200) {
      ref.read(pagingControllerProvider(_key).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ExpensePagingState paging =
        ref.watch(pagingControllerProvider(_key));
    final AsyncValue<Trip> tripAsync = ref.watch(tripDetailProvider(widget.tripId));
    final ExpenseFilterState filter =
        ref.watch(expenseFilterProvider(widget.tripId));
    final DemoStore store = ref.read(demoStoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TRIP EXPENSES'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.donut_large_outlined),
            tooltip: 'Chart view',
            onPressed: () => context.go(
              '/m/trips/${widget.tripId}/expenses/all/chart',
            ),
          ),
          _FilterButton(
            count: filter.count,
            onTap: () => showExpenseFilterSheet(
              context,
              tripId: widget.tripId,
              showMembers: true,
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const SyncStatusBanner(),
          _ScopeTabs(tripId: widget.tripId, active: 'all'),
          if (filter.count > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              color: AppColors.cream,
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.filter_alt,
                    size: 16,
                    color: AppColors.brandBrown,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${filter.count} filter${filter.count == 1 ? '' : 's'} active',
                      style: const TextStyle(
                        color: AppColors.brandBrown,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref
                            .read(expenseFilterProvider(widget.tripId).notifier)
                            .state =
                        const ExpenseFilterState(),
                    child: const Text('CLEAR'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: tripAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, _) => Center(child: Text('Error: $e')),
              data: (Trip trip) => _PagedTripList(
                paging: paging,
                trip: trip,
                store: store,
                filter: filter,
                scrollCtrl: _scrollCtrl,
                onTapRow: (Expense e) => context.go(
                  '/m/trips/${widget.tripId}/expenses/${e.id}',
                ),
                onRefresh: () => ref
                    .read(pagingControllerProvider(_key).notifier)
                    .refresh(),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: TripBottomNav(
        tripId: widget.tripId,
        currentLocation: GoRouterState.of(context).matchedLocation,
      ),
    );
  }
}

class _PagedTripList extends StatelessWidget {
  const _PagedTripList({
    required this.paging,
    required this.trip,
    required this.store,
    required this.filter,
    required this.scrollCtrl,
    required this.onTapRow,
    required this.onRefresh,
  });

  final ExpensePagingState paging;
  final Trip trip;
  final DemoStore store;
  final ExpenseFilterState filter;
  final ScrollController scrollCtrl;
  final ValueChanged<Expense> onTapRow;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    if (paging.loading && paging.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (paging.error != null && paging.items.isEmpty) {
      return Center(child: Text('${l.common_error}: ${paging.error}'));
    }
    final List<Expense> rows =
        filter.isEmpty ? paging.items : _applyFilter(paging.items, filter);
    if (rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: <Widget>[
            const SizedBox(height: 80),
            Center(
              child: Text(
                l.expense_list_empty,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),
          ],
        ),
      );
    }
    final int footerCount =
        paging.loadingMore || (!paging.hasMore && paging.items.isNotEmpty)
            ? 1
            : 0;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: rows.length + footerCount,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (BuildContext context, int i) {
          if (i >= rows.length) return _PagingFooter(paging: paging);
          final Expense e = rows[i];
          return _ExpenseRow(
            expense: e,
            store: store,
            onTap: () => onTapRow(e),
          );
        },
      ),
    );
  }

  List<Expense> _applyFilter(
    List<Expense> items,
    ExpenseFilterState filter,
  ) {
    return items.where((Expense e) {
      if (filter.categoryCodes.isNotEmpty &&
          !filter.categoryCodes.contains(e.categoryCode)) {
        return false;
      }
      if (filter.sourceIds.isNotEmpty &&
          !filter.sourceIds.contains(e.sourceId)) {
        return false;
      }
      if (filter.memberIds.isNotEmpty &&
          !filter.memberIds.contains(e.userId)) {
        return false;
      }
      if (filter.from != null && e.occurredAt.isBefore(filter.from!)) {
        return false;
      }
      if (filter.to != null && e.occurredAt.isAfter(filter.to!)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }
}

class _PagingFooter extends StatelessWidget {
  const _PagingFooter({required this.paging});
  final ExpensePagingState paging;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    if (paging.loadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              l.expense_list_loadingMore,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: Text(
          l.expense_list_endOfList,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 1.4,
              ),
        ),
      ),
    );
  }
}

class _ScopeTabs extends StatelessWidget {
  const _ScopeTabs({required this.tripId, required this.active});
  final String tripId;
  final String active;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: <Widget>[
          _Tab(
            label: 'MY EXPENSES',
            active: active == 'mine',
            onTap: () =>
                GoRouter.of(context).go('/m/trips/$tripId/expenses/mine'),
          ),
          _Tab(
            label: 'TRIP EXPENSES',
            active: active == 'all',
            onTap: () =>
                GoRouter.of(context).go('/m/trips/$tripId/expenses/all'),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(AppRadii.chip),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.brandBrown : Colors.transparent,
            borderRadius: const BorderRadius.all(AppRadii.chip),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.cream : AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.filter_alt_outlined),
          tooltip: 'Filter',
          onPressed: onTap,
        ),
        if (count > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: const BoxDecoration(
                color: AppColors.outflow,
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.expense,
    required this.store,
    required this.onTap,
  });

  final Expense expense;
  final DemoStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceCard,
      borderRadius: const BorderRadius.all(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _AmountCircle(amount: expense.amount.format()),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      store.userById(expense.userId).displayName.toUpperCase(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.goldOlive,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.forCategory(expense.categoryCode),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          expense.categoryCode,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                letterSpacing: 1.2,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          _shortDate(expense.occurredAt),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      expense.details.isEmpty ? '(no details)' : expense.details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortDate(DateTime d) {
    const List<String> months = <String>[
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

class _AmountCircle extends StatelessWidget {
  const _AmountCircle({required this.amount});
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.goldOlive.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.goldOlive, width: 2),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: FittedBox(
          child: Text(
            amount,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.brandBrown,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
