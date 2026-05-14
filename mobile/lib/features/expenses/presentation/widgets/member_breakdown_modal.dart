import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/fake/demo_store.dart';
import '../../../../core/money/money.dart';
import '../../../trips/application/trips_providers.dart';
import '../../../trips/domain/trip.dart';
import '../../application/expenses_providers.dart';
import '../../data/expense_repository.dart';
import '../../domain/expense.dart';

Future<void> showMemberBreakdownModal(
  BuildContext context, {
  required String tripId,
  required String memberId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext _) =>
        _MemberBreakdownModal(tripId: tripId, memberId: memberId),
  );
}

class _MemberBreakdownModal extends ConsumerWidget {
  const _MemberBreakdownModal({required this.tripId, required this.memberId});
  final String tripId;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Trip> tripAsync = ref.watch(tripDetailProvider(tripId));
    final AsyncValue<List<ExpenseSummary>> summaryAsync = ref.watch(
      _memberSummaryProvider((tripId: tripId, memberId: memberId)),
    );
    final DemoStore store = ref.read(demoStoreProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (BuildContext context, ScrollController scroll) {
        return Column(
          children: <Widget>[
            const _GrabHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      store.userById(memberId).displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: tripAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, _) => Center(child: Text('Error: $e')),
                data: (Trip trip) => summaryAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (Object e, _) => Center(child: Text('Error: $e')),
                  data: (List<ExpenseSummary> rows) {
                    if (rows.isEmpty) {
                      return Center(
                        child: Text(
                          'No expenses yet for this member.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      );
                    }
                    final Money total = rows.fold(
                      Money.zero(trip.currency),
                      (Money a, ExpenseSummary b) => a + b.amount,
                    );
                    return SingleChildScrollView(
                      controller: scroll,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: <Widget>[
                          SizedBox(
                            width: 220,
                            height: 220,
                            child: Stack(
                              alignment: Alignment.center,
                              children: <Widget>[
                                PieChart(
                                  PieChartData(
                                    sectionsSpace: 2,
                                    centerSpaceRadius: 64,
                                    sections: <PieChartSectionData>[
                                      for (final ExpenseSummary s in rows)
                                        PieChartSectionData(
                                          value: s.amount.amountMinor.toDouble(),
                                          color: AppColors.forCategory(
                                            s.groupKey,
                                          ),
                                          radius: 30,
                                          showTitle: false,
                                        ),
                                    ],
                                  ),
                                ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    Text(
                                      'SPENT',
                                      style: Theme.of(context).textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                            letterSpacing: 1.4,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      total.format(),
                                      style: Theme.of(context).textTheme
                                          .titleLarge
                                          ?.copyWith(
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
                                      color: AppColors.forCategory(s.groupKey),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      _categoryLabel(store, s.groupKey),
                                      style: Theme.of(context).textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                                  Text(
                                    s.amount.format(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _categoryLabel(DemoStore store, String code) {
    try {
      return store.categoryByCode(code).nameEn;
    } catch (_) {
      return code;
    }
  }
}

final FutureProviderFamily<
  List<ExpenseSummary>,
  ({String tripId, String memberId})
>
_memberSummaryProvider =
    FutureProvider.family<
      List<ExpenseSummary>,
      ({String tripId, String memberId})
    >((Ref ref, ({String tripId, String memberId}) args) async {
      return ref
          .read(expenseRepositoryProvider)
          .summary(
            tripId: args.tripId,
            scope: ExpenseSummaryScope.user,
            groupBy: ExpenseGroupBy.category,
            userId: args.memberId,
          );
    });

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
