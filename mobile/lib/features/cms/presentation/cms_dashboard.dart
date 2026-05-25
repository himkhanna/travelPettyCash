import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart' show AppRadii, AppSpacing;
import '../../../core/api/hydration_service.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../audit/application/audit_providers.dart';
import '../../audit/domain/audit_entry.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../expenses/application/expenses_providers.dart';
import '../../expenses/domain/expense.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/domain/funding.dart';
import '../../missions/application/mission_providers.dart';
import '../../missions/domain/mission.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import 'create_trip_dialog.dart';
import 'widgets/cms_layout.dart';
import 'widgets/cms_theme.dart';

// ============================================================================
// Aggregate provider — fans out per-trip expense + allocation reads.
// ============================================================================

class DashboardData {
  const DashboardData({
    required this.trips,
    required this.missions,
    required this.expenses,
    required this.allocations,
    required this.sources,
    required this.audit,
  });
  final List<Trip> trips;
  final List<Mission> missions;
  final List<Expense> expenses;
  final List<Allocation> allocations;
  final List<Source> sources;
  final List<AuditEntry> audit;
}

final FutureProvider<DashboardData> dashboardDataProvider =
    FutureProvider<DashboardData>((Ref ref) async {
  final List<Trip> trips = await ref.watch(adminAllTripsProvider.future);
  final List<List<Expense>> perTripExpenses =
      await Future.wait(<Future<List<Expense>>>[
    for (final Trip t in trips)
      ref.read(expenseRepositoryProvider).list(tripId: t.id),
  ]);
  final List<List<Allocation>> perTripAllocs =
      await Future.wait(<Future<List<Allocation>>>[
    for (final Trip t in trips)
      ref.read(allocationRepositoryProvider).forTrip(t.id),
  ]);
  final List<Mission> missions =
      await ref.watch(missionsProvider.future);
  final List<Source> sources = await ref.watch(sourcesProvider.future);
  List<AuditEntry> audit = const <AuditEntry>[];
  try {
    audit = await ref.watch(auditFeedProvider.future);
  } catch (_) {
    audit = const <AuditEntry>[];
  }
  return DashboardData(
    trips: trips,
    missions: missions,
    expenses: <Expense>[for (final List<Expense> c in perTripExpenses) ...c],
    allocations: <Allocation>[
      for (final List<Allocation> c in perTripAllocs) ...c
    ],
    sources: sources,
    audit: audit,
  );
});

/// All trips visible to Admin/SuperAdmin. Exposed at module scope so
/// trip detail can invalidate it after edits.
final FutureProvider<List<Trip>> adminAllTripsProvider =
    FutureProvider<List<Trip>>((Ref ref) async {
  final User? user = await ref.watch(currentUserProvider.future);
  if (user == null) return <Trip>[];
  return ref.read(tripRepositoryProvider).allTrips();
});

// ============================================================================
// Screen
// ============================================================================

class CmsDashboard extends ConsumerWidget {
  const CmsDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<User?> userAsync = ref.watch(currentUserProvider);
    final User? me = userAsync.valueOrNull;
    if (me == null) {
      if (userAsync.hasValue) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/portal');
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (me.role != UserRole.admin && me.role != UserRole.superAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go('/wrong-portal?expected=mobileApp');
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final AsyncValue<bool> hydrationAsync =
        ref.watch(authenticatedHydrationProvider);
    final AsyncValue<DashboardData> dataAsync =
        ref.watch(dashboardDataProvider);

    return CmsLayout(
      active: CmsNavItem.home,
      showTitleStrip: false,
      trailing: <Widget>[
        if (me.role == UserRole.admin)
          ElevatedButton.icon(
            onPressed: () => _openCreateTrip(context, ref),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New trip'),
            style: ElevatedButton.styleFrom(
              backgroundColor: CmsColors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
      rightRail: hydrationAsync.maybeWhen(
        data: (bool _) => dataAsync.maybeWhen(
          data: (DashboardData d) => _RightRail(data: d),
          orElse: () => const SizedBox.shrink(),
        ),
        orElse: () => const SizedBox.shrink(),
      ),
      child: hydrationAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (bool ready) => !ready
            ? const Center(child: CircularProgressIndicator())
            : dataAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (Object e, _) => Center(child: Text('Error: $e')),
                data: (DashboardData d) => _Body(me: me, data: d),
              ),
      ),
    );
  }

  Future<void> _openCreateTrip(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final bool? created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) => const CreateTripDialog(),
    );
    if (created == true) {
      ref.invalidate(adminAllTripsProvider);
      ref.invalidate(dashboardDataProvider);
    }
  }
}

// ============================================================================
// Body
// ============================================================================

class _Body extends StatelessWidget {
  const _Body({required this.me, required this.data});
  final User me;
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final _Aggregates agg = _Aggregates.from(data);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Greeting(me: me, agg: agg),
          const SizedBox(height: 18),
          _KpiRow(agg: agg, data: data),
          const SizedBox(height: 22),
          _NeedsAttention(data: data, agg: agg),
          const SizedBox(height: 22),
          _ActiveTripsSection(data: data, agg: agg),
        ],
      ),
    );
  }
}

// ============================================================================
// Aggregates
// ============================================================================

class _Aggregates {
  _Aggregates({
    required this.activeTrips,
    required this.totalTrips,
    required this.spend30d,
    required this.spend30dPrev,
    required this.budgetRemaining,
    required this.totalBudget,
    required this.approvalsPending,
    required this.approvalsUrgent,
    required this.dominantCurrency,
    required this.spendByDay,
    required this.spentByTrip,
    required this.spentByMission,
    required this.overBudgetTrips,
    required this.nearBudgetTrips,
    required this.receiptsMissing,
  });

  final int activeTrips;
  final int totalTrips;
  final int spend30d;
  final int spend30dPrev;
  final int budgetRemaining;
  final int totalBudget;
  final int approvalsPending;
  final int approvalsUrgent;
  final String dominantCurrency;

  /// Day buckets for the right-rail spend chart — index 0 = 30d ago,
  /// 29 = today. Values are minor units in [dominantCurrency].
  final List<int> spendByDay;

  /// Trip id → total spent (in trip's own currency).
  final Map<String, Money> spentByTrip;
  /// Mission id → spent (in dominant currency only — multi-currency mix
  /// would make the right-rail comparison meaningless).
  final Map<String, int> spentByMission;

  final List<Trip> overBudgetTrips;
  /// Trips at ≥85% but <100% of budget.
  final List<Trip> nearBudgetTrips;
  /// Count of expenses without an attached receipt.
  final int receiptsMissing;

  static _Aggregates from(DashboardData d) {
    final Map<String, Trip> tripById = <String, Trip>{
      for (final Trip t in d.trips) t.id: t,
    };
    final List<Trip> active = d.trips
        .where((Trip t) => t.status == TripStatus.active)
        .toList();

    // Pick dominant currency from active trips (fallback to all).
    String dominant(Iterable<Trip> set) {
      final Map<String, int> tally = <String, int>{};
      for (final Trip t in set) {
        tally.update(t.currency, (int v) => v + 1, ifAbsent: () => 1);
      }
      if (tally.isEmpty) return 'AED';
      return tally.entries
          .reduce((MapEntry<String, int> a, MapEntry<String, int> b) =>
              a.value >= b.value ? a : b)
          .key;
    }
    final String dom = active.isNotEmpty ? dominant(active) : dominant(d.trips);

    // 30-day spend bucket: only count expenses in [dom] currency to keep
    // the headline comparable. Cross-currency aggregation would mislead.
    final DateTime now = DateTime.now();
    final DateTime start30 = now.subtract(const Duration(days: 30));
    final DateTime startPrev = now.subtract(const Duration(days: 60));
    final List<int> byDay = List<int>.filled(30, 0);
    int spend = 0;
    int spendPrev = 0;
    final Map<String, Money> spentByTrip = <String, Money>{};
    final Map<String, int> spentByMission = <String, int>{};
    int receiptsMissing = 0;
    for (final Expense e in d.expenses) {
      if (e.receiptObjectKey == null) receiptsMissing++;
      spentByTrip.update(
        e.tripId,
        (Money v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
      final Trip? trip = tripById[e.tripId];
      if (trip == null) continue;
      if (trip.currency != dom) continue;
      final int minor = e.amount.amountMinor;
      if (e.occurredAt.isAfter(start30)) {
        spend += minor;
        final int dayIdx = 29 -
            now.difference(e.occurredAt).inDays.clamp(0, 29);
        byDay[dayIdx] += minor;
      } else if (e.occurredAt.isAfter(startPrev)) {
        spendPrev += minor;
      }
      if (trip.missionId != null) {
        spentByMission.update(
          trip.missionId!,
          (int v) => v + minor,
          ifAbsent: () => minor,
        );
      }
    }

    // Budget remaining: trip.totalBudget in dominant currency only.
    int totalBudget = 0;
    for (final Trip t in active) {
      if (t.currency != dom) continue;
      totalBudget += t.totalBudget.amountMinor;
    }
    final int remaining = totalBudget - spend;

    // Approvals: pending allocations addressed to anyone, plus the audit-
    // flagged "needs review" rows. Urgent = older than 2 days.
    final List<Allocation> pendingAllocs = d.allocations
        .where((Allocation a) => a.status == AllocationStatus.pending)
        .toList();
    int urgent = 0;
    final DateTime twoDaysAgo =
        DateTime.now().subtract(const Duration(days: 2));
    for (final Allocation a in pendingAllocs) {
      if (a.createdAt.isBefore(twoDaysAgo)) urgent++;
    }

    // Over-budget & near-budget detection per active trip.
    final List<Trip> overBudget = <Trip>[];
    final List<Trip> nearBudget = <Trip>[];
    for (final Trip t in active) {
      final Money? spentM = spentByTrip[t.id];
      if (spentM == null || t.totalBudget.isZero) continue;
      final double ratio =
          spentM.amountMinor / t.totalBudget.amountMinor;
      if (ratio >= 1.0) {
        overBudget.add(t);
      } else if (ratio >= 0.85) {
        nearBudget.add(t);
      }
    }

    return _Aggregates(
      activeTrips: active.length,
      totalTrips: d.trips.length,
      spend30d: spend,
      spend30dPrev: spendPrev,
      budgetRemaining: remaining,
      totalBudget: totalBudget,
      approvalsPending: pendingAllocs.length,
      approvalsUrgent: urgent,
      dominantCurrency: dom,
      spendByDay: byDay,
      spentByTrip: spentByTrip,
      spentByMission: spentByMission,
      overBudgetTrips: overBudget,
      nearBudgetTrips: nearBudget,
      receiptsMissing: receiptsMissing,
    );
  }
}

// ============================================================================
// Greeting + summary line
// ============================================================================

class _Greeting extends StatelessWidget {
  const _Greeting({required this.me, required this.agg});
  final User me;
  final _Aggregates agg;

  @override
  Widget build(BuildContext context) {
    final int h = DateTime.now().hour;
    final String greet = h < 12
        ? 'Good morning'
        : h < 17
            ? 'Good afternoon'
            : 'Good evening';
    final String first = me.displayName.split(' ').first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                DateFormat('EEEE · MMM d, yyyy')
                    .format(DateTime.now())
                    .toUpperCase(),
                style: const TextStyle(
                  color: CmsColors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$greet, $first.',
                style: const TextStyle(
                  color: CmsColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _summaryLine(),
                style: const TextStyle(
                  color: CmsColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _summaryLine() {
    final List<String> parts = <String>[];
    parts.add(
      '${agg.activeTrips} active trip${agg.activeTrips == 1 ? '' : 's'}',
    );
    if (agg.approvalsPending > 0) {
      parts.add(
        '${agg.approvalsPending} approval'
        '${agg.approvalsPending == 1 ? '' : 's'} need${agg.approvalsPending == 1 ? 's' : ''} you',
      );
    }
    if (agg.overBudgetTrips.isNotEmpty) {
      parts.add(
        '${agg.overBudgetTrips.length} trip'
        '${agg.overBudgetTrips.length == 1 ? '' : 's'} over budget today',
      );
    }
    return '${parts.join(', ')}.';
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {},
      icon: Icon(icon, size: 14, color: CmsColors.textBody),
      label: Text(
        label,
        style: const TextStyle(
          color: CmsColors.textBody,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: CmsColors.divider),
        backgroundColor: CmsColors.surfaceCard,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// ============================================================================
// KPI row — 4 cards each with a sparkline
// ============================================================================

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.agg, required this.data});
  final _Aggregates agg;
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final int totalExpenses = data.expenses.length;
    final DateTime sevenDaysAgo =
        DateTime.now().subtract(const Duration(days: 7));
    final int expenses7d = data.expenses
        .where((Expense e) => e.occurredAt.isAfter(sevenDaysAgo))
        .length;
    final double receiptCoveragePct = totalExpenses == 0
        ? 100
        : ((totalExpenses - agg.receiptsMissing) / totalExpenses) * 100;

    return LayoutBuilder(
      builder: (BuildContext _, BoxConstraints c) {
        final int cols =
            c.maxWidth >= 1100 ? 4 : c.maxWidth >= 720 ? 2 : 1;
        const double gap = 12;
        final double w = (c.maxWidth - (cols - 1) * gap) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            SizedBox(
              width: w,
              child: _KpiCard(
                label: 'Active trips',
                value: '${agg.activeTrips}',
                subtitle: 'of ${agg.totalTrips} total',
                trendUp: true,
                sparkline: _sparkline(agg.spendByDay),
              ),
            ),
            SizedBox(
              width: w,
              child: _KpiCard(
                label: 'Expenses logged',
                value: '$totalExpenses',
                subtitle: expenses7d > 0
                    ? '+$expenses7d in last 7 days'
                    : 'no new this week',
                trendUp: expenses7d > 0,
                sparkline: _sparkline(agg.spendByDay),
              ),
            ),
            SizedBox(
              width: w,
              child: _KpiCard(
                label: 'Receipts missing',
                value: '${agg.receiptsMissing}',
                subtitle: agg.receiptsMissing == 0
                    ? 'all expenses have receipts'
                    : '${receiptCoveragePct.toStringAsFixed(0)}% '
                        'of $totalExpenses have receipts',
                trendUp: agg.receiptsMissing == 0,
                sparkline: _sparkline(agg.spendByDay),
              ),
            ),
            SizedBox(
              width: w,
              child: _KpiCard(
                label: 'Pending fund transfers',
                value: '${agg.approvalsPending}',
                subtitle: agg.approvalsPending == 0
                    ? 'no funds awaiting acceptance'
                    : agg.approvalsUrgent > 0
                        ? '${agg.approvalsUrgent} older than 2 days'
                        : 'all received this week',
                trendUp:
                    agg.approvalsUrgent == 0 && agg.approvalsPending == 0,
                sparkline: _sparkline(agg.spendByDay),
              ),
            ),
          ],
        );
      },
    );
  }

  List<FlSpot> _sparkline(List<int> values) {
    return <FlSpot>[
      for (int i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i].toDouble()),
    ];
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.trendUp,
    required this.sparkline,
  });
  final String label;
  final String value;
  final String subtitle;
  final bool trendUp;
  final List<FlSpot> sparkline;

  @override
  Widget build(BuildContext context) {
    final Color trendColor = trendUp ? CmsColors.accent : CmsColors.outflow;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: CmsColors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: CmsColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.0,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 28,
            child: sparkline.isEmpty
                ? const SizedBox.shrink()
                : LineChart(
                    LineChartData(
                      lineTouchData: const LineTouchData(enabled: false),
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: <LineChartBarData>[
                        LineChartBarData(
                          spots: sparkline,
                          isCurved: true,
                          curveSmoothness: 0.3,
                          barWidth: 1.6,
                          color: trendColor,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: trendColor.withValues(alpha: 0.08),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: trendUp ? CmsColors.accent : CmsColors.outflow,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Needs your attention
// ============================================================================

class _NeedsAttention extends ConsumerWidget {
  const _NeedsAttention({required this.data, required this.agg});
  final DashboardData data;
  final _Aggregates agg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DemoStore store = ref.read(demoStoreProvider);
    final List<_AttentionCard> alerts = <_AttentionCard>[];

    for (final Trip t in agg.overBudgetTrips.take(2)) {
      final Money spent = agg.spentByTrip[t.id] ?? Money.zero(t.currency);
      final Money over = spent - t.totalBudget;
      alerts.add(_AttentionCard(
        icon: Icons.priority_high,
        iconBg: CmsColors.redSoft,
        iconColor: CmsColors.outflow,
        title: '${t.name} is over budget',
        subtitle:
            '${spent.format()} / ${t.totalBudget.format()} · +${over.format()}',
        ctaLabel: 'Review',
        onTap: () => context.go('/cms/trips/${t.id}'),
      ));
    }
    if (agg.approvalsPending > 0) {
      alerts.add(_AttentionCard(
        icon: Icons.check_box_outlined,
        iconBg: CmsColors.brandTint,
        iconColor: CmsColors.brand,
        title: '${agg.approvalsPending} '
            'expense${agg.approvalsPending == 1 ? '' : 's'} '
            'awaiting your approval',
        subtitle: agg.approvalsUrgent > 0
            ? '${agg.approvalsUrgent} urgent · oldest > 2 days'
            : 'all received in the last 2 days',
        ctaLabel: 'Approve queue',
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Approvals queue: coming soon')),
        ),
      ));
    }
    for (final Trip t in agg.nearBudgetTrips.take(2)) {
      final Money spent = agg.spentByTrip[t.id] ?? Money.zero(t.currency);
      final double pct = t.totalBudget.isZero
          ? 0
          : (spent.amountMinor / t.totalBudget.amountMinor) * 100;
      alerts.add(_AttentionCard(
        icon: Icons.warning_amber_outlined,
        iconBg: CmsColors.amberSoft,
        iconColor: CmsColors.warning,
        title: '${t.name} is approaching budget cap',
        subtitle:
            '${spent.format()} / ${t.totalBudget.format()} · ${pct.toStringAsFixed(0)}% used',
        ctaLabel: 'Open trip',
        onTap: () => context.go('/cms/trips/${t.id}'),
      ));
    }
    if (agg.receiptsMissing > 0) {
      // Surface up to 2 trip names that have the missing receipts.
      final Set<String> tripIds = data.expenses
          .where((Expense e) => e.receiptObjectKey == null)
          .map((Expense e) => e.tripId)
          .toSet();
      final List<String> names = tripIds
          .map((String id) {
            try {
              return store.tripById(id).name;
            } catch (_) {
              return null;
            }
          })
          .whereType<String>()
          .take(2)
          .toList();
      alerts.add(_AttentionCard(
        icon: Icons.receipt_long_outlined,
        iconBg: CmsColors.bgElev,
        iconColor: CmsColors.textSecondary,
        title: '${agg.receiptsMissing} '
            'receipt${agg.receiptsMissing == 1 ? '' : 's'} missing context',
        subtitle: names.isEmpty
            ? 'Spread across multiple trips'
            : 'Across ${names.join(' and ')}',
        ctaLabel: 'Triage',
        onTap: () => context.go('/cms/expenses?missingReceipt=1'),
      ));
    }

    if (alerts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionHeader(
          icon: Icons.flash_on,
          title: 'Needs your attention',
          badge: '${alerts.length}',
          trailingLabel: 'View all',
          onTrailingTap: () {},
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: CmsColors.surfaceCard,
            borderRadius: const BorderRadius.all(AppRadii.card),
            border: Border.all(color: CmsColors.divider),
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < alerts.length; i++) ...<Widget>[
                if (i > 0)
                  const Divider(height: 1, color: CmsColors.divider),
                alerts[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.onTap,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CmsColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CmsColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onTap,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward, size: 13),
            label: Text(ctaLabel),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: CmsColors.divider),
              foregroundColor: CmsColors.textPrimary,
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Active trips table
// ============================================================================

class _ActiveTripsSection extends ConsumerStatefulWidget {
  const _ActiveTripsSection({required this.data, required this.agg});
  final DashboardData data;
  final _Aggregates agg;

  @override
  ConsumerState<_ActiveTripsSection> createState() =>
      _ActiveTripsSectionState();
}

class _ActiveTripsSectionState extends ConsumerState<_ActiveTripsSection> {
  TripStatus _filter = TripStatus.active;

  @override
  Widget build(BuildContext context) {
    final Map<String, Mission> missionById = <String, Mission>{
      for (final Mission m in widget.data.missions) m.id: m,
    };
    final DemoStore store = ref.read(demoStoreProvider);
    final List<Trip> visible = widget.data.trips
        .where((Trip t) => t.status == _filter)
        .toList()
      ..sort((Trip a, Trip b) => b.createdAt.compareTo(a.createdAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const _SectionTitle(
              icon: Icons.flight_takeoff_outlined,
              title: 'Active trips',
            ),
            const SizedBox(width: 8),
            _Badge(label: '${visible.length}'),
            const Spacer(),
            _Tabs(
              current: _filter,
              onChange: (TripStatus s) => setState(() => _filter = s),
            ),
            const SizedBox(width: 8),
            _GhostButton(icon: Icons.filter_list, label: 'Filter'),
            const SizedBox(width: 6),
            _GhostButton(icon: Icons.sort, label: 'Sort'),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: CmsColors.surfaceCard,
            borderRadius: const BorderRadius.all(AppRadii.card),
            border: Border.all(color: CmsColors.divider),
          ),
          child: Column(
            children: <Widget>[
              _TripTableHeader(),
              for (int i = 0; i < visible.length; i++) ...<Widget>[
                if (i > 0)
                  const Divider(height: 1, color: CmsColors.divider),
                _TripTableRow(
                  trip: visible[i],
                  mission: visible[i].missionId == null
                      ? null
                      : missionById[visible[i].missionId!],
                  spent: widget.agg.spentByTrip[visible[i].id],
                  store: store,
                ),
              ],
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No trips in this view.',
                      style: TextStyle(color: CmsColors.textSecondary),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.current, required this.onChange});
  final TripStatus current;
  final ValueChanged<TripStatus> onChange;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: CmsColors.bgElev,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final TripStatus s in TripStatus.values)
            _TabBtn(
              label: _labelFor(s),
              selected: current == s,
              onTap: () => onChange(s),
            ),
        ],
      ),
    );
  }

  String _labelFor(TripStatus s) => switch (s) {
        TripStatus.active => 'Active',
        TripStatus.draft => 'Drafts',
        TripStatus.closed => 'Closed',
      };
}

class _TabBtn extends StatelessWidget {
  const _TabBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CmsColors.surfaceCard : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: selected
                  ? CmsColors.textPrimary
                  : CmsColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TripTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    TextStyle h() => const TextStyle(
          color: CmsColors.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CmsColors.divider)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: 90, child: Text('TRIP', style: h())),
          Expanded(flex: 3, child: Text('', style: h())),
          Expanded(flex: 3, child: Text('MISSION', style: h())),
          Expanded(flex: 2, child: Text('LEAD', style: h())),
          Expanded(flex: 3, child: Text('BUDGET', style: h())),
          Expanded(flex: 2, child: Text('MEMBERS', style: h())),
          SizedBox(width: 70, child: Text('OPEN', style: h())),
          SizedBox(width: 80, child: Text('CREATED', style: h())),
          const SizedBox(width: 28),
        ],
      ),
    );
  }
}

class _TripTableRow extends StatelessWidget {
  const _TripTableRow({
    required this.trip,
    required this.mission,
    required this.spent,
    required this.store,
  });
  final Trip trip;
  final Mission? mission;
  final Money? spent;
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    final double pct = spent == null || trip.totalBudget.isZero
        ? 0
        : (spent!.amountMinor / trip.totalBudget.amountMinor)
            .clamp(0.0, 1.0)
            .toDouble();
    final Color budgetColor = pct >= 0.98
        ? CmsColors.outflow
        : pct >= 0.85
            ? CmsColors.warning
            : CmsColors.accent;
    String leadName;
    try {
      leadName = store.userById(trip.leaderId).displayName;
    } catch (_) {
      leadName = '—';
    }

    return InkWell(
      onTap: () => GoRouter.of(context).go('/cms/trips/${trip.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 90,
              child: Row(
                children: <Widget>[
                  Text(_flag(trip.countryCode),
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    trip.countryCode.toUpperCase(),
                    style: const TextStyle(
                      color: CmsColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    trip.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CmsColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'T-${trip.id.substring(trip.id.length - 4).toUpperCase()} · ${trip.countryName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CmsColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: mission == null
                  ? const Text(
                      '—',
                      style: TextStyle(color: CmsColors.textTertiary),
                    )
                  : Row(
                      children: <Widget>[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _missionColor(mission!.id),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            mission!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CmsColors.textBody,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: CmsColors.brandTint,
                    child: Text(
                      _initials(leadName),
                      style: const TextStyle(
                        color: CmsColors.textPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      leadName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CmsColors.textBody,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          spent == null
                              ? '— / ${trip.totalBudget.format()}'
                              : '${_compact(spent!.amountMinor)} / ${_compact(trip.totalBudget.amountMinor)} ${trip.currency}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CmsColors.textBody,
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Text(
                        '${(pct * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: budgetColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 4,
                      backgroundColor: CmsColors.bgElev,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(budgetColor),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: _MemberAvatars(
                memberIds: trip.memberIds,
                store: store,
              ),
            ),
            SizedBox(
              width: 70,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: CmsColors.amberSoft,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${trip.memberIds.length + 1} OPEN',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CmsColors.warning,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                DateFormat('MMM d, yyyy').format(trip.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CmsColors.textBody,
                  fontSize: 11.5,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.more_horiz,
              size: 16,
              color: CmsColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberAvatars extends StatelessWidget {
  const _MemberAvatars({required this.memberIds, required this.store});
  final List<String> memberIds;
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    final List<String> firstThree = memberIds.take(3).toList();
    final int extra = memberIds.length - firstThree.length;
    return Row(
      children: <Widget>[
        for (int i = 0; i < firstThree.length; i++)
          Transform.translate(
            offset: Offset(-8.0 * i, 0),
            child: CircleAvatar(
              radius: 11,
              backgroundColor: _avatarBg(i),
              child: Text(
                _avatarInitial(firstThree[i]),
                style: const TextStyle(
                  color: CmsColors.surfaceCard,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        if (extra > 0)
          Transform.translate(
            offset: Offset(-8.0 * firstThree.length, 0),
            child: CircleAvatar(
              radius: 11,
              backgroundColor: CmsColors.bgElev,
              child: Text(
                '+$extra',
                style: const TextStyle(
                  color: CmsColors.textPrimary,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _avatarInitial(String userId) {
    try {
      final String name = store.userById(userId).displayName;
      final List<String> parts = name.split(' ');
      if (parts.isEmpty) return '?';
      return parts.first[0].toUpperCase();
    } catch (_) {
      return '?';
    }
  }

  Color _avatarBg(int i) {
    const List<Color> palette = <Color>[
      Color(0xFF8B6B3A),
      Color(0xFF6B8A3F),
      Color(0xFFA85C2A),
    ];
    return palette[i % palette.length];
  }
}

// ============================================================================
// Right rail — spend chart + missions list + recent activity
// ============================================================================

class _RightRail extends StatelessWidget {
  const _RightRail({required this.data});
  final DashboardData data;
  @override
  Widget build(BuildContext context) {
    final _Aggregates agg = _Aggregates.from(data);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SpendChartCard(agg: agg),
          const SizedBox(height: 14),
          _MissionsCard(data: data, agg: agg),
          const SizedBox(height: 14),
          _RecentActivityCard(audit: data.audit),
        ],
      ),
    );
  }
}

class _SpendChartCard extends StatelessWidget {
  const _SpendChartCard({required this.agg});
  final _Aggregates agg;
  @override
  Widget build(BuildContext context) {
    final NumberFormat fmt = NumberFormat.decimalPattern('en_US');
    final double delta = agg.spend30dPrev == 0
        ? 0
        : ((agg.spend30d - agg.spend30dPrev) / agg.spend30dPrev) * 100;
    final double maxVal = agg.spendByDay.fold<int>(0,
            (int a, int b) => b > a ? b : a).toDouble().clamp(1, double.infinity);

    return _RailCard(
      title: 'Spend · Last 30 days',
      trailingLabel: 'Reporting',
      onTrailingTap: () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${agg.dominantCurrency} ${fmt.format(agg.spend30d / 100.0)}',
            style: const TextStyle(
              color: CmsColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          Row(
            children: <Widget>[
              Text(
                delta == 0
                    ? '—'
                    : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: delta >= 0 ? CmsColors.accent : CmsColors.outflow,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'MoM',
                style: TextStyle(
                  color: CmsColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: BarChart(
              BarChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                alignment: BarChartAlignment.spaceBetween,
                maxY: maxVal,
                barTouchData: BarTouchData(enabled: false),
                barGroups: <BarChartGroupData>[
                  for (int i = 0; i < agg.spendByDay.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: <BarChartRodData>[
                        BarChartRodData(
                          toY: agg.spendByDay[i].toDouble(),
                          color: CmsColors.accent.withValues(alpha: 0.7),
                          width: 4,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Text(
                _shortDate(DateTime.now().subtract(const Duration(days: 30))),
                style: const TextStyle(
                  color: CmsColors.textTertiary,
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              Text(
                _shortDate(DateTime.now().subtract(const Duration(days: 15))),
                style: const TextStyle(
                  color: CmsColors.textTertiary,
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              Text(
                _shortDate(DateTime.now()),
                style: const TextStyle(
                  color: CmsColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shortDate(DateTime d) => DateFormat('MMM d').format(d);
}

class _MissionsCard extends StatelessWidget {
  const _MissionsCard({required this.data, required this.agg});
  final DashboardData data;
  final _Aggregates agg;
  @override
  Widget build(BuildContext context) {
    final NumberFormat fmt = NumberFormat.compact(locale: 'en');
    // Compute per-mission spend + budget. Budget = sum of trip budgets
    // in dominant currency that reference this mission.
    final Map<String, int> budgetByMission = <String, int>{};
    final Map<String, int> tripsCountByMission = <String, int>{};
    for (final Trip t in data.trips) {
      if (t.missionId == null) continue;
      if (t.currency != agg.dominantCurrency) continue;
      budgetByMission.update(
        t.missionId!,
        (int v) => v + t.totalBudget.amountMinor,
        ifAbsent: () => t.totalBudget.amountMinor,
      );
      tripsCountByMission.update(
        t.missionId!,
        (int v) => v + 1,
        ifAbsent: () => 1,
      );
    }
    final List<_MissionRow> rows = <_MissionRow>[];
    for (final Mission m in data.missions) {
      final int budget = budgetByMission[m.id] ?? 0;
      final int spent = agg.spentByMission[m.id] ?? 0;
      final int trips = tripsCountByMission[m.id] ?? 0;
      if (budget == 0 && spent == 0) continue;
      rows.add(_MissionRow(
        name: m.name,
        spent: spent,
        budget: budget,
        trips: trips,
      ));
    }
    rows.sort((_MissionRow a, _MissionRow b) {
      final double ar = a.budget == 0 ? 0 : a.spent / a.budget;
      final double br = b.budget == 0 ? 0 : b.spent / b.budget;
      return br.compareTo(ar);
    });

    return _RailCard(
      title: 'Missions · Spend vs Budget',
      trailingLabel: 'All',
      onTrailingTap: () => GoRouter.of(context).go('/cms/missions'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'No mission spend yet.',
                style: TextStyle(color: CmsColors.textSecondary, fontSize: 12),
              ),
            )
          else
            for (int i = 0; i < rows.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 10),
              _MissionRowView(
                row: rows[i],
                color: CmsColors.missionPalette[i % CmsColors.missionPalette.length],
                currency: agg.dominantCurrency,
                fmt: fmt,
              ),
            ],
        ],
      ),
    );
  }
}

class _MissionRow {
  const _MissionRow({
    required this.name,
    required this.spent,
    required this.budget,
    required this.trips,
  });
  final String name;
  final int spent;
  final int budget;
  final int trips;
}

class _MissionRowView extends StatelessWidget {
  const _MissionRowView({
    required this.row,
    required this.color,
    required this.currency,
    required this.fmt,
  });
  final _MissionRow row;
  final Color color;
  final String currency;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final double pct = row.budget == 0
        ? 0
        : (row.spent / row.budget).clamp(0.0, 1.5).toDouble();
    final double barFill = pct.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CmsColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: pct >= 1.0 ? CmsColors.outflow : CmsColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Container(
            height: 5,
            color: CmsColors.bgElev,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: barFill,
              child: Container(color: color),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Text(
              '$currency ${fmt.format(row.spent / 100.0)} of '
              '$currency ${fmt.format(row.budget / 100.0)}',
              style: const TextStyle(
                color: CmsColors.textSecondary,
                fontSize: 10.5,
              ),
            ),
            const Spacer(),
            Text(
              '${row.trips} trip${row.trips == 1 ? '' : 's'}',
              style: const TextStyle(
                color: CmsColors.textTertiary,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.audit});
  final List<AuditEntry> audit;
  @override
  Widget build(BuildContext context) {
    final List<AuditEntry> head = audit.take(5).toList();
    return _RailCard(
      title: 'Recent activity',
      trailingLabel: 'View log',
      onTrailingTap: () => GoRouter.of(context).go('/cms/audit'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (head.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'No activity yet.',
                style: TextStyle(color: CmsColors.textSecondary, fontSize: 12),
              ),
            )
          else
            for (int i = 0; i < head.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 8),
              _ActivityRow(e: head[i]),
            ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.e});
  final AuditEntry e;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: e.tripId == null
          ? null
          : () => GoRouter.of(context).go('/cms/trips/${e.tripId}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 10,
            backgroundColor: _avatarColor(e.action),
            child: Text(
              _initials(e.actorName),
              style: const TextStyle(
                color: CmsColors.surfaceCard,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${e.actorName.split(' ').last} ${_actionVerb(e.action)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CmsColors.textBody,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
                if (e.tripName != null)
                  Text(
                    '${e.tripName} · ${_timeAgo(e.at)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CmsColors.textTertiary,
                      fontSize: 10.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _avatarColor(AuditAction a) {
    switch (a) {
      case AuditAction.expenseLogged:
        return CmsColors.accent;
      case AuditAction.allocationFromAdmin:
      case AuditAction.allocationFromLeader:
      case AuditAction.allocationAccepted:
        return CmsColors.brand;
      case AuditAction.allocationDeclined:
      case AuditAction.transferDeclined:
        return CmsColors.outflow;
      case AuditAction.tripCreated:
      case AuditAction.tripClosed:
        return CmsColors.warning;
      default:
        return CmsColors.textSecondary;
    }
  }

  String _actionVerb(AuditAction a) {
    switch (a) {
      case AuditAction.tripCreated:
        return 'created a trip';
      case AuditAction.tripClosed:
        return 'closed a trip';
      case AuditAction.allocationFromAdmin:
      case AuditAction.allocationFromLeader:
        return 'allocated funds';
      case AuditAction.allocationAccepted:
        return 'accepted an allocation';
      case AuditAction.allocationDeclined:
        return 'declined an allocation';
      case AuditAction.transferSent:
        return 'sent a transfer';
      case AuditAction.transferAccepted:
        return 'accepted a transfer';
      case AuditAction.transferDeclined:
        return 'declined a transfer';
      case AuditAction.expenseLogged:
        return e.amount == null
            ? 'submitted an expense'
            : 'submitted an expense of ${e.amount!.format()}';
      case AuditAction.userSignedIn:
        return 'signed in';
      case AuditAction.userCreated:
        return 'added a new user';
      case AuditAction.userUpdated:
        return 'updated a user';
    }
  }
}

// ============================================================================
// Shared bits
// ============================================================================

class _RailCard extends StatelessWidget {
  const _RailCard({
    required this.title,
    required this.trailingLabel,
    required this.onTrailingTap,
    required this.child,
  });
  final String title;
  final String trailingLabel;
  final VoidCallback onTrailingTap;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: CmsColors.textTertiary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              InkWell(
                onTap: onTrailingTap,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        trailingLabel,
                        style: const TextStyle(
                          color: CmsColors.textSecondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.arrow_forward,
                        size: 11,
                        color: CmsColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.badge,
    required this.trailingLabel,
    required this.onTrailingTap,
  });
  final IconData icon;
  final String title;
  final String badge;
  final String trailingLabel;
  final VoidCallback onTrailingTap;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _SectionTitle(icon: icon, title: title),
        const SizedBox(width: 8),
        _Badge(label: badge),
        const Spacer(),
        InkWell(
          onTap: onTrailingTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              trailingLabel,
              style: const TextStyle(
                color: CmsColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: CmsColors.textPrimary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: CmsColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: CmsColors.bgElev,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: CmsColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ============================================================================
// Helpers
// ============================================================================

String _flag(String code) {
  if (code.length != 2) return '🏳';
  const int base = 0x1F1E6;
  final int a = code.toUpperCase().codeUnitAt(0) - 0x41 + base;
  final int b = code.toUpperCase().codeUnitAt(1) - 0x41 + base;
  return String.fromCharCodes(<int>[a, b]);
}

String _initials(String name) {
  final List<String> parts =
      name.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

String _compact(int minor) =>
    NumberFormat.compact(locale: 'en').format(minor / 100.0);

String _timeAgo(DateTime at) {
  final Duration d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return DateFormat('MMM d').format(at);
}

Color _missionColor(String id) {
  final int hash = id.hashCode.abs();
  return CmsColors.missionPalette[hash % CmsColors.missionPalette.length];
}
