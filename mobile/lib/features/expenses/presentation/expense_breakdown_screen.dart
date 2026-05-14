import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../auth/application/auth_providers.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../data/expense_repository.dart';
import '../domain/expense.dart';
import 'expense_breakdown_screen.providers.dart';

/// Screen-inventory #11 — My Expenses category breakdown chart.
/// Multi-segment donut + legend; BY CATEGORY / BY SOURCE tab switcher.
class ExpenseBreakdownScreen extends ConsumerStatefulWidget {
  const ExpenseBreakdownScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<ExpenseBreakdownScreen> createState() =>
      _ExpenseBreakdownScreenState();
}

class _ExpenseBreakdownScreenState
    extends ConsumerState<ExpenseBreakdownScreen> {
  ExpenseGroupBy _groupBy = ExpenseGroupBy.category;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Trip> tripAsync = ref.watch(
      tripDetailProvider(widget.tripId),
    );
    final AsyncValue<List<ExpenseSummary>> summaryAsync = ref.watch(
      mySummaryProvider((tripId: widget.tripId, groupBy: _groupBy)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('MY EXPENSES'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'List view',
            onPressed: () =>
                context.go('/m/trips/${widget.tripId}/expenses/mine'),
          ),
        ],
      ),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (Trip trip) => Column(
          children: <Widget>[
            _GroupTabs(
              groupBy: _groupBy,
              onChanged: (ExpenseGroupBy g) => setState(() => _groupBy = g),
            ),
            Expanded(
              child: summaryAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, _) => Center(child: Text('Error: $e')),
                data: (List<ExpenseSummary> rows) => _BreakdownBody(
                  rows: rows,
                  currency: trip.currency,
                  groupBy: _groupBy,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: TripBottomNav(
        tripId: widget.tripId,
        currentLocation: GoRouterState.of(context).matchedLocation,
      ),
    );
  }
}

class _GroupTabs extends StatelessWidget {
  const _GroupTabs({required this.groupBy, required this.onChanged});
  final ExpenseGroupBy groupBy;
  final ValueChanged<ExpenseGroupBy> onChanged;

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
          for (final ExpenseGroupBy g in <ExpenseGroupBy>[
            ExpenseGroupBy.category,
            ExpenseGroupBy.source,
          ])
            Expanded(
              child: InkWell(
                onTap: () => onChanged(g),
                borderRadius: const BorderRadius.all(AppRadii.chip),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: groupBy == g
                        ? AppColors.brandBrown
                        : Colors.transparent,
                    borderRadius: const BorderRadius.all(AppRadii.chip),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'BY ${g == ExpenseGroupBy.category ? 'CATEGORY' : 'SOURCE'}',
                    style: TextStyle(
                      color: groupBy == g
                          ? AppColors.cream
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BreakdownBody extends ConsumerWidget {
  const _BreakdownBody({
    required this.rows,
    required this.currency,
    required this.groupBy,
  });

  final List<ExpenseSummary> rows;
  final String currency;
  final ExpenseGroupBy groupBy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'No expenses yet.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    final Money total = rows.fold(
      Money.zero(currency),
      (Money a, ExpenseSummary b) => a + b.amount,
    );

    final DemoStore store = ref.read(demoStoreProvider);

    Color colorFor(ExpenseSummary s) {
      if (groupBy == ExpenseGroupBy.category) {
        return AppColors.forCategory(s.groupKey);
      }
      // Source colors — use brand alternates.
      return _sourceColors[rows.indexOf(s) % _sourceColors.length];
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: <Widget>[
          SizedBox(
            width: 240,
            height: 240,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 70,
                    sections: <PieChartSectionData>[
                      for (final ExpenseSummary s in rows)
                        PieChartSectionData(
                          value: s.amount.amountMinor.toDouble(),
                          color: colorFor(s),
                          radius: 32,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      'TOTAL SPEND',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      total.format(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandBrown,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final ExpenseSummary s in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colorFor(s),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _labelFor(s, store),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    s.amount.format(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _labelFor(ExpenseSummary s, DemoStore store) {
    if (groupBy == ExpenseGroupBy.category) {
      return store.categoryByCode(s.groupKey).nameEn;
    }
    return s.label;
  }
}

const List<Color> _sourceColors = <Color>[
  AppColors.brandBrown,
  AppColors.goldOlive,
  AppColors.success,
  AppColors.warning,
];
