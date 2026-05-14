import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/expenses_providers.dart';
import '../domain/expense.dart';
import 'widgets/expense_filter_sheet.dart';

/// Screen-inventory #26 — Trip Expenses (all members) for Leader/Admin/SuperAdmin.
class TripExpensesScreen extends ConsumerWidget {
  const TripExpensesScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Expense>> async = ref.watch(
      tripExpensesProvider(tripId),
    );
    final AsyncValue<Trip> tripAsync = ref.watch(tripDetailProvider(tripId));
    final ExpenseFilterState filter = ref.watch(expenseFilterProvider(tripId));
    final DemoStore store = ref.read(demoStoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TRIP EXPENSES'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.donut_large_outlined),
            tooltip: 'Chart view',
            onPressed: () => context.go(
              '/m/trips/$tripId/expenses/all/chart',
            ),
          ),
          _FilterButton(
            count: filter.count,
            onTap: () => showExpenseFilterSheet(
              context,
              tripId: tripId,
              showMembers: true,
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const SyncStatusBanner(),
          _ScopeTabs(tripId: tripId, active: 'all'),
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
                    onPressed: () =>
                        ref.read(expenseFilterProvider(tripId).notifier).state =
                            const ExpenseFilterState(),
                    child: const Text('CLEAR'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, _) => Center(child: Text('Error: $e')),
              data: (List<Expense> rows) => tripAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, _) => Center(child: Text('Error: $e')),
                data: (Trip trip) => rows.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (BuildContext context, int i) {
                          final Expense e = rows[i];
                          return _ExpenseRow(
                            expense: e,
                            store: store,
                            onTap: () => context.go(
                              '/m/trips/$tripId/expenses/${e.id}',
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: TripBottomNav(
        tripId: tripId,
        currentLocation: GoRouterState.of(context).matchedLocation,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'No expenses match the current filter.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
