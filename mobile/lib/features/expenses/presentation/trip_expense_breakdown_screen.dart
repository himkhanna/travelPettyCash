import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../auth/application/auth_providers.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import '../application/expenses_providers.dart';
import '../data/expense_repository.dart';
import '../domain/expense.dart';
import 'widgets/member_breakdown_modal.dart';

/// Trip-wide breakdown with BY CATEGORY / BY MEMBER / BY SOURCE tabs
/// (screen-inventory #28 / #29 / #30 entry).
class TripExpenseBreakdownScreen extends ConsumerStatefulWidget {
  const TripExpenseBreakdownScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<TripExpenseBreakdownScreen> createState() =>
      _TripExpenseBreakdownScreenState();
}

class _TripExpenseBreakdownScreenState
    extends ConsumerState<TripExpenseBreakdownScreen> {
  ExpenseGroupBy _groupBy = ExpenseGroupBy.category;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Trip> tripAsync = ref.watch(
      tripDetailProvider(widget.tripId),
    );
    final AsyncValue<List<ExpenseSummary>> summaryAsync = ref.watch(
      _allSummaryProvider((tripId: widget.tripId, groupBy: _groupBy)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('TRIP EXPENSES'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'List view',
            onPressed: () =>
                context.go('/m/trips/${widget.tripId}/expenses/all'),
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
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (Object e, _) => Center(child: Text('Error: $e')),
                data: (List<ExpenseSummary> rows) => _BreakdownBody(
                  rows: rows,
                  currency: trip.currency,
                  groupBy: _groupBy,
                  tripId: widget.tripId,
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

final FutureProviderFamily<
  List<ExpenseSummary>,
  ({String tripId, ExpenseGroupBy groupBy})
>
_allSummaryProvider =
    FutureProvider.family<
      List<ExpenseSummary>,
      ({String tripId, ExpenseGroupBy groupBy})
    >((Ref ref, ({String tripId, ExpenseGroupBy groupBy}) args) async {
      await ref.watch(currentUserProvider.future);
      ref.watch(fakeRoleProvider);
      ref.watch(syncStateProvider);
      return ref
          .read(expenseRepositoryProvider)
          .summary(
            tripId: args.tripId,
            scope: ExpenseSummaryScope.all,
            groupBy: args.groupBy,
          );
    });

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
          for (final ExpenseGroupBy g in ExpenseGroupBy.values)
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
                    _label(g),
                    style: TextStyle(
                      color: groupBy == g
                          ? AppColors.cream
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _label(ExpenseGroupBy g) {
    switch (g) {
      case ExpenseGroupBy.category:
        return 'BY CATEGORY';
      case ExpenseGroupBy.source:
        return 'BY SOURCE';
      case ExpenseGroupBy.member:
        return 'BY MEMBER';
    }
  }
}

class _BreakdownBody extends ConsumerWidget {
  const _BreakdownBody({
    required this.rows,
    required this.currency,
    required this.groupBy,
    required this.tripId,
  });

  final List<ExpenseSummary> rows;
  final String currency;
  final ExpenseGroupBy groupBy;
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'No expenses yet.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    final Money total = rows.fold(
      Money.zero(currency),
      (Money a, ExpenseSummary b) => a + b.amount,
    );

    final DemoStore store = ref.read(demoStoreProvider);

    Color colorFor(int index, ExpenseSummary s) {
      if (groupBy == ExpenseGroupBy.category) {
        return AppColors.forCategory(s.groupKey);
      }
      return _palette[index % _palette.length];
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
                      for (int i = 0; i < rows.length; i++)
                        PieChartSectionData(
                          value: rows[i].amount.amountMinor.toDouble(),
                          color: colorFor(i, rows[i]),
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
                      'TOTAL TRIP SPEND',
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
          for (int i = 0; i < rows.length; i++)
            InkWell(
              onTap: groupBy == ExpenseGroupBy.member
                  ? () => showMemberBreakdownModal(
                      context,
                      tripId: tripId,
                      memberId: rows[i].groupKey,
                    )
                  : null,
              borderRadius: const BorderRadius.all(AppRadii.chip),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colorFor(i, rows[i]),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _labelFor(rows[i], store),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      rows[i].amount.format(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (groupBy == ExpenseGroupBy.member)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _labelFor(ExpenseSummary s, DemoStore store) {
    switch (groupBy) {
      case ExpenseGroupBy.category:
        try {
          return store.categoryByCode(s.groupKey).nameEn;
        } catch (_) {
          return s.label;
        }
      case ExpenseGroupBy.source:
        try {
          return store.sourceById(s.groupKey).name;
        } catch (_) {
          return s.label;
        }
      case ExpenseGroupBy.member:
        try {
          return store.userById(s.groupKey).displayName;
        } catch (_) {
          return s.label;
        }
    }
  }
}

const List<Color> _palette = <Color>[
  AppColors.brandBrown,
  AppColors.goldOlive,
  AppColors.success,
  AppColors.warning,
  AppColors.outflow,
  Color(0xFF7B5BA8),
  Color(0xFF4F7CB8),
];
