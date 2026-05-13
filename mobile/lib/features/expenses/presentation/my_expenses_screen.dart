import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/expenses_providers.dart';
import '../domain/expense.dart';

/// Screen-inventory #7 — My Expenses list. List/chart toggle routes to
/// the breakdown chart (#11) which lands in the next slice.
class MyExpensesScreen extends ConsumerWidget {
  const MyExpensesScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Expense>> expenses = ref.watch(
      myExpensesProvider(tripId),
    );
    final AsyncValue<Trip> tripAsync = ref.watch(tripDetailProvider(tripId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('MY EXPENSES'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.donut_large_outlined),
            tooltip: 'Chart view',
            onPressed: () => context.go('/m/trips/$tripId/expenses/mine/chart'),
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: 'Filter',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Filters land later in Milestone A.'),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const SyncStatusBanner(),
          Expanded(
            child: expenses.when(
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
                            trip: trip,
                            onTap: () =>
                                context.go('/m/trips/$tripId/expenses/${e.id}'),
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

class _ExpenseRow extends ConsumerWidget {
  const _ExpenseRow({
    required this.expense,
    required this.trip,
    required this.onTap,
  });
  final Expense expense;
  final Trip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String dateStr = _shortDate(expense.occurredAt);
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
                          dateStr,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      expense.details.isEmpty
                          ? '(no details)'
                          : expense.details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (expense.pendingSync) ...<Widget>[
                      const SizedBox(height: 6),
                      const _PendingChip(),
                    ],
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
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
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

class _PendingChip extends StatelessWidget {
  const _PendingChip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.18),
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.cloud_off, size: 13, color: AppColors.warning),
          const SizedBox(width: 4),
          Text(
            'Pending sync',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: AppColors.goldOlive,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No expenses yet — tap the + button to record one.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
