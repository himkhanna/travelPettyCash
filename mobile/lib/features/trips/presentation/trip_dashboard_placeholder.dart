import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../application/trips_providers.dart';
import '../domain/trip.dart';

/// Stand-in dashboard until #3/#4 lands in the next Milestone A slice.
/// Confirms routing, trip resolution, and balance fetch work end-to-end.
class TripDashboardPlaceholder extends ConsumerWidget {
  const TripDashboardPlaceholder({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Trip> trip = ref.watch(tripDetailProvider(tripId));
    final AsyncValue<TripBalances> balances = ref
        .watch(tripBalancesProvider((tripId: tripId, scope: BalanceScope.me)));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/m/trips'),
        ),
        title: trip.maybeWhen(
          data: (Trip t) => Text(t.countryName.toUpperCase()),
          orElse: () => const Text('Trip'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              trip.when(
                data: (Trip t) => Text(
                  t.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                loading: () => const SizedBox.shrink(),
                error: (Object e, _) => Text('Error: $e'),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: balances.when(
                  data: (TripBalances b) => _BalanceSummary(balances: b),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (Object e, _) => Center(child: Text('Error: $e')),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: const BorderRadius.all(AppRadii.card),
                ),
                child: Text(
                  'Full dashboard (donut + per-source cards + drawer) lands in '
                  'the next Milestone A slice.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceSummary extends StatelessWidget {
  const _BalanceSummary({required this.balances});
  final TripBalances balances;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Row(label: 'TOTAL BUDGET', value: balances.totalBudget.format()),
        _Row(label: 'TOTAL SPENT', value: balances.totalSpent.format()),
        _Row(label: 'TOTAL BALANCE', value: balances.totalBalance.format()),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'PER SOURCE',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 1.4,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final SourceBalance s in balances.perSource) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: const BorderRadius.all(AppRadii.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(s.sourceName,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.arrow_downward,
                          color: AppColors.inflow, size: 16),
                      const SizedBox(width: 4),
                      Text(s.received.format(),
                          style: const TextStyle(color: AppColors.inflow)),
                      const SizedBox(width: AppSpacing.md),
                      const Icon(Icons.arrow_upward,
                          color: AppColors.outflow, size: 16),
                      const SizedBox(width: 4),
                      Text(s.spent.format(),
                          style: const TextStyle(color: AppColors.outflow)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'BALANCE  ${s.balance.format()}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.goldOlive,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 1.2,
                  )),
          Text(value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
        ],
      ),
    );
  }
}
