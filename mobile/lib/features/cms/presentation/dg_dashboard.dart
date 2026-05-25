import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import 'widgets/cms_theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../expenses/application/expenses_providers.dart';
import '../../expenses/domain/expense.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import 'widgets/cms_layout.dart';

/// Cross-trip rollup for the Director General view. Fans out one API call
/// per trip to collect expenses, then aggregates client-side. A dedicated
/// backend aggregate endpoint would be cheaper at scale; for the current
/// trip volume the fan-out is fine and avoids a parallel schema.
final FutureProvider<({List<Trip> trips, List<Expense> expenses})>
    dgAggregateProvider = FutureProvider<({List<Trip> trips, List<Expense> expenses})>(
  (Ref ref) async {
    final List<Trip> trips =
        await ref.read(tripRepositoryProvider).allTrips();
    final List<List<Expense>> perTrip = await Future.wait(<Future<List<Expense>>>[
      for (final Trip t in trips)
        ref.read(expenseRepositoryProvider).list(tripId: t.id),
    ]);
    final List<Expense> all = <Expense>[
      for (final List<Expense> chunk in perTrip) ...chunk,
    ];
    return (trips: trips, expenses: all);
  },
);

/// Read-only oversight view per CLAUDE.md §1 — the Director General sees
/// every trip, every balance, every spend without action affordances.
class DgDashboard extends ConsumerWidget {
  const DgDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<({List<Trip> trips, List<Expense> expenses})> aggAsync =
        ref.watch(dgAggregateProvider);

    return aggAsync.when(
      loading: () => const CmsLayout(
        active: CmsNavItem.dg,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object e, _) => CmsLayout(
        active: CmsNavItem.dg,
        child: Center(child: Text('Could not load DG view: $e')),
      ),
      data: (({List<Trip> trips, List<Expense> expenses}) agg) {
        final List<Trip> trips = agg.trips;
        final List<Expense> expenses = agg.expenses;

        // Active trips list
        final List<Trip> activeTrips = trips
            .where((Trip t) => t.status == TripStatus.active)
            .toList();

        // Per-trip totals
        final Map<String, Trip> tripById = <String, Trip>{
          for (final Trip t in trips) t.id: t,
        };
        final Map<String, Money> spentByTrip = <String, Money>{};
        for (final Expense e in expenses) {
          final Trip? trip = tripById[e.tripId];
          if (trip == null) continue;
          spentByTrip.update(
            e.tripId,
            (Money v) => v + e.amount,
            ifAbsent: () => e.amount,
          );
        }

        // Per-category roll-up (currency may differ across trips — keyed in
        // each trip's own currency, summed only within same-currency group).
        final Map<String, Money> byCategorySameCurrency = <String, Money>{};
        final String dominantCurrency = trips.isEmpty
            ? 'SAR'
            : trips
                  .map((Trip t) => t.currency)
                  .fold(
                    <String, int>{},
                    (Map<String, int> m, String c) =>
                        m..update(c, (int v) => v + 1, ifAbsent: () => 1),
                  )
                  .entries
                  .reduce(
                    (MapEntry<String, int> a, MapEntry<String, int> b) =>
                        a.value >= b.value ? a : b,
                  )
                  .key;

        for (final Expense e in expenses) {
          final Trip? trip = tripById[e.tripId];
          if (trip == null) continue;
          if (trip.currency != dominantCurrency) continue;
          byCategorySameCurrency.update(
            e.categoryCode,
            (Money v) => v + e.amount,
            ifAbsent: () => e.amount,
          );
        }

        return CmsLayout(
      active: CmsNavItem.dg,
      trailing: const <Widget>[
        Chip(
          label: Text(
            'READ-ONLY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          backgroundColor: CmsColors.cream,
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SummaryRow(
                trips: trips,
                activeTrips: activeTrips,
                expenses: expenses,
                spentByTrip: spentByTrip,
                dominantCurrency: dominantCurrency,
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: _TripsTable(
                      trips: trips,
                      spentByTrip: spentByTrip,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    flex: 2,
                    child: _CategoryDonut(
                      data: byCategorySameCurrency,
                      currency: dominantCurrency,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.trips,
    required this.activeTrips,
    required this.expenses,
    required this.spentByTrip,
    required this.dominantCurrency,
  });

  final List<Trip> trips;
  final List<Trip> activeTrips;
  final List<Expense> expenses;
  final Map<String, Money> spentByTrip;
  final String dominantCurrency;

  @override
  Widget build(BuildContext context) {
    final Money totalBudget = trips
        .where((Trip t) => t.currency == dominantCurrency)
        .fold(
          Money.zero(dominantCurrency),
          (Money a, Trip t) => a + t.totalBudget,
        );
    final Money totalSpent = expenses
        .where(
          (Expense e) =>
              trips.any(
                (Trip t) => t.id == e.tripId && t.currency == dominantCurrency,
              ),
        )
        .fold<Money>(
          Money.zero(dominantCurrency),
          (Money a, Expense b) => a + b.amount,
        );

    return Row(
      children: <Widget>[
        Expanded(
          child: _Stat(
            label: 'ACTIVE TRIPS',
            value: activeTrips.length.toString(),
            color: CmsColors.success,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _Stat(
            label: 'TOTAL TRIPS',
            value: trips.length.toString(),
            color: CmsColors.brandBrown,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _Stat(
            label: 'TOTAL BUDGET',
            value: totalBudget.format(),
            color: CmsColors.brandBrown,
            small: true,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _Stat(
            label: 'TOTAL SPENT',
            value: totalSpent.format(),
            color: CmsColors.outflow,
            small: true,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _Stat(
            label: 'REMAINING ($dominantCurrency)',
            value: (totalBudget - totalSpent).format(),
            color: CmsColors.goldOlive,
            small: true,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.color,
    this.small = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: CmsColors.textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: small ? 18 : 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripsTable extends StatelessWidget {
  const _TripsTable({required this.trips, required this.spentByTrip});

  final List<Trip> trips;
  final Map<String, Money> spentByTrip;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: CmsColors.cream,
              borderRadius: BorderRadius.vertical(top: AppRadii.card),
            ),
            child: Row(
              children: const <Widget>[
                Expanded(flex: 3, child: _Th(label: 'TRIP')),
                Expanded(flex: 2, child: _Th(label: 'STATUS')),
                Expanded(flex: 2, child: _Th(label: 'BUDGET')),
                Expanded(flex: 2, child: _Th(label: 'SPENT')),
                Expanded(flex: 2, child: _Th(label: 'BALANCE')),
              ],
            ),
          ),
          for (final Trip t in trips) ...<Widget>[
            const Divider(height: 1, color: CmsColors.divider),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: <Widget>[
                        Text(
                          _flag(t.countryCode),
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      t.status.name.toUpperCase(),
                      style: TextStyle(
                        color: _statusColor(t.status),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  Expanded(flex: 2, child: Text(t.totalBudget.format())),
                  Expanded(
                    flex: 2,
                    child: Text(
                      (spentByTrip[t.id] ?? Money.zero(t.currency)).format(),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      (t.totalBudget -
                              (spentByTrip[t.id] ?? Money.zero(t.currency)))
                          .format(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(TripStatus s) {
    switch (s) {
      case TripStatus.active:
        return CmsColors.success;
      case TripStatus.draft:
        return CmsColors.warning;
      case TripStatus.closed:
        return CmsColors.textSecondary;
    }
  }

  String _flag(String code) {
    if (code.length != 2) return '🏳️';
    const int base = 0x1F1E6;
    final int a = code.toUpperCase().codeUnitAt(0) - 0x41 + base;
    final int b = code.toUpperCase().codeUnitAt(1) - 0x41 + base;
    return String.fromCharCodes(<int>[a, b]);
  }
}

class _Th extends StatelessWidget {
  const _Th({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: CmsColors.textSecondary,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _CategoryDonut extends ConsumerWidget {
  const _CategoryDonut({required this.data, required this.currency});
  final Map<String, Money> data;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DemoStore store = ref.read(demoStoreProvider);
    if (data.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: CmsColors.surfaceCard,
          borderRadius: const BorderRadius.all(AppRadii.card),
          border: Border.all(color: CmsColors.divider),
        ),
        child: const Center(child: Text('No spend yet.')),
      );
    }
    final Money total = data.values.fold(
      Money.zero(currency),
      (Money a, Money b) => a + b,
    );
    final List<MapEntry<String, Money>> rows = data.entries.toList()
      ..sort(
        (MapEntry<String, Money> a, MapEntry<String, Money> b) =>
            b.value.amountMinor.compareTo(a.value.amountMinor),
      );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'SPEND BY CATEGORY ($currency)',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: CmsColors.textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 60,
                    sections: <PieChartSectionData>[
                      for (final MapEntry<String, Money> e in rows)
                        PieChartSectionData(
                          value: e.value.amountMinor.toDouble(),
                          color: CmsColors.forCategory(e.key),
                          radius: 28,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      'TOTAL',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: CmsColors.textSecondary,
                      ),
                    ),
                    Text(
                      total.format(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: CmsColors.brandBrown,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final MapEntry<String, Money> e in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: CmsColors.forCategory(e.key),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(_safeName(store, e.key))),
                  Text(
                    e.value.format(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _safeName(DemoStore store, String code) {
    try {
      return store.categoryByCode(code).nameEn;
    } catch (_) {
      return code;
    }
  }
}
