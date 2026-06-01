import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart' show AppRadii;
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../expenses/domain/expense.dart';
import '../../missions/application/mission_providers.dart';
import '../../missions/domain/mission.dart';
import '../../reports/application/report_download_providers.dart';
import '../../reports/data/report_download_repository.dart';
import '../../reports/data/report_schedule_repository.dart';
import '../../reports/presentation/save_to_disk.dart';
import '../../trips/domain/trip.dart';
import 'cms_dashboard.dart' show DashboardData, dashboardDataProvider;
import 'widgets/cms_layout.dart';
import 'widgets/cms_theme.dart';

/// Detail page for a single mission. Reached by clicking a mission name
/// on the Missions card grid. Shows everything tied to that mission:
/// description, parent/child links, every trip with budget+spend bar,
/// scheduled deliveries pointing at this mission, and a one-tap rollup
/// download.
class CmsMissionDetailScreen extends ConsumerWidget {
  const CmsMissionDetailScreen({super.key, required this.missionId});
  final String missionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    if (me == null ||
        (me.role != UserRole.admin && me.role != UserRole.superAdmin)) {
      return const CmsLayout(
        active: CmsNavItem.missions,
        title: 'Mission',
        child: Center(child: Text('Admin only.')),
      );
    }

    final AsyncValue<List<Mission>> missionsAsync =
        ref.watch(missionsProvider);
    final AsyncValue<DashboardData> dataAsync =
        ref.watch(dashboardDataProvider);
    final AsyncValue<List<ReportScheduleRow>> schedulesAsync =
        ref.watch(reportSchedulesProvider);

    return missionsAsync.when(
      loading: () => const CmsLayout(
        active: CmsNavItem.missions,
        title: 'Loading…',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object e, _) => CmsLayout(
        active: CmsNavItem.missions,
        title: 'Mission not found',
        child: Center(child: Text('Error: $e')),
      ),
      data: (List<Mission> missions) {
        final Mission? m =
            missions.where((Mission m) => m.id == missionId).firstOrNull;
        if (m == null) {
          return CmsLayout(
            active: CmsNavItem.missions,
            title: 'Mission not found',
            breadcrumb: const <String>['Home', 'Missions', 'Not found'],
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'This mission no longer exists.',
                      style: TextStyle(color: CmsColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => context.go('/cms/missions'),
                      child: const Text('Back to Missions'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return CmsLayout(
          active: CmsNavItem.missions,
          title: m.name,
          titleSubtitle:
              '${m.code} · ${m.status == MissionStatus.closed ? "Closed" : "Active"}',
          trailing: <Widget>[
            TextButton.icon(
              onPressed: () => context.go('/cms/missions'),
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('All missions'),
              style: TextButton.styleFrom(
                foregroundColor: CmsColors.surfaceCard,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _downloadRollup(context, ref, m.id),
              icon: const Icon(Icons.download, size: 14),
              label: const Text('Download rollup'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CmsColors.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
          child: dataAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object e, _) => Center(child: Text('Error: $e')),
            data: (DashboardData d) => _Body(
              mission: m,
              allMissions: missions,
              data: d,
              schedules: schedulesAsync.valueOrNull ??
                  const <ReportScheduleRow>[],
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadRollup(
    BuildContext context, WidgetRef ref, String mid,
  ) async {
    try {
      final report = await ref.read(reportDownloadRepositoryProvider).download(
            kind: ReportDownloadKind.missionRollup,
            missionId: mid,
          );
      saveBytesToDisk(
        bytes: report.bytes,
        filename: report.filename,
        contentType: report.contentType,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded ${report.filename}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rollup failed: $e'),
          backgroundColor: CmsColors.outflow,
        ),
      );
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.mission,
    required this.allMissions,
    required this.data,
    required this.schedules,
  });
  final Mission mission;
  final List<Mission> allMissions;
  final DashboardData data;
  final List<ReportScheduleRow> schedules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DemoStore store = ref.read(demoStoreProvider);
    final List<Trip> missionTrips = data.trips
        .where((Trip t) => t.missionId == mission.id)
        .toList()
      ..sort((Trip a, Trip b) => b.createdAt.compareTo(a.createdAt));
    final Map<String, Money> spentByTrip = <String, Money>{};
    for (final Expense e in data.expenses) {
      spentByTrip.update(
        e.tripId,
        (Money v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
    }
    final Map<String, int> totalSpentByCcy = <String, int>{};
    final Map<String, int> totalBudgetByCcy = <String, int>{};
    for (final Trip t in missionTrips) {
      totalBudgetByCcy.update(
        t.currency,
        (int v) => v + t.totalBudget.amountMinor,
        ifAbsent: () => t.totalBudget.amountMinor,
      );
      final Money? s = spentByTrip[t.id];
      if (s != null) {
        totalSpentByCcy.update(
          s.currencyCode,
          (int v) => v + s.amountMinor,
          ifAbsent: () => s.amountMinor,
        );
      }
    }

    final Mission? parent = mission.parentMissionId == null
        ? null
        : allMissions
            .where((Mission m) => m.id == mission.parentMissionId)
            .firstOrNull;
    final List<Mission> children = allMissions
        .where((Mission m) => m.parentMissionId == mission.id)
        .toList();
    final List<ReportScheduleRow> tied = schedules
        .where((ReportScheduleRow s) =>
            s.scope == ScheduleScope.mission && s.scopeId == mission.id)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _HeaderCard(
            mission: mission,
            parent: parent,
            children: children,
            totalBudgetByCcy: totalBudgetByCcy,
            totalSpentByCcy: totalSpentByCcy,
            tripCount: missionTrips.length,
          ),
          const SizedBox(height: 14),
          _SectionLabel(
            label: 'Trips',
            count: missionTrips.length,
          ),
          const SizedBox(height: 8),
          _TripsCard(
            trips: missionTrips, spentByTrip: spentByTrip, store: store,
          ),
          const SizedBox(height: 14),
          _SectionLabel(label: 'Scheduled deliveries', count: tied.length),
          const SizedBox(height: 8),
          _SchedulesCard(tied: tied),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: CmsColors.textPrimary,
            fontSize: 13, fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: CmsColors.bgElev,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: CmsColors.textPrimary,
              fontSize: 11, fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.mission,
    required this.parent,
    required this.children,
    required this.totalBudgetByCcy,
    required this.totalSpentByCcy,
    required this.tripCount,
  });
  final Mission mission;
  final Mission? parent;
  final List<Mission> children;
  final Map<String, int> totalBudgetByCcy;
  final Map<String, int> totalSpentByCcy;
  final int tripCount;

  @override
  Widget build(BuildContext context) {
    final NumberFormat fmt = NumberFormat.compact(locale: 'en');
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (mission.description != null &&
              mission.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                mission.description!,
                style: const TextStyle(
                  color: CmsColors.textBody,
                  fontSize: 13, height: 1.4,
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _Pill(
                icon: Icons.flight_takeoff_outlined,
                label: '$tripCount '
                    'trip${tripCount == 1 ? '' : 's'}',
                accent: CmsColors.brand,
              ),
              for (final MapEntry<String, int> e
                  in totalBudgetByCcy.entries)
                _Pill(
                  icon: Icons.account_balance_outlined,
                  label: 'Budget ${e.key} ${fmt.format(e.value / 100.0)}',
                  accent: CmsColors.textSecondary,
                ),
              for (final MapEntry<String, int> e
                  in totalSpentByCcy.entries)
                _Pill(
                  icon: Icons.receipt_long_outlined,
                  label: 'Spent ${e.key} ${fmt.format(e.value / 100.0)}',
                  accent: CmsColors.outflow,
                ),
              if (parent != null)
                _Pill(
                  icon: Icons.subdirectory_arrow_right,
                  label: 'Parent: ${parent!.name}',
                  accent: CmsColors.goldDeep,
                ),
              if (children.isNotEmpty)
                _Pill(
                  icon: Icons.account_tree_outlined,
                  label: '${children.length} child '
                      'mission${children.length == 1 ? '' : 's'}',
                  accent: CmsColors.brand,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon, required this.label, required this.accent,
  });
  final IconData icon;
  final String label;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 11.5, fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripsCard extends StatelessWidget {
  const _TripsCard({
    required this.trips,
    required this.spentByTrip,
    required this.store,
  });
  final List<Trip> trips;
  final Map<String, Money> spentByTrip;
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: trips.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'No trips assigned to this mission yet.',
                  style: TextStyle(color: CmsColors.textSecondary),
                ),
              ),
            )
          : Column(
              children: <Widget>[
                for (int i = 0; i < trips.length; i++) ...<Widget>[
                  if (i > 0)
                    const Divider(height: 1, color: CmsColors.divider),
                  _TripRow(
                    trip: trips[i],
                    spent: spentByTrip[trips[i].id],
                    store: store,
                  ),
                ],
              ],
            ),
    );
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow({
    required this.trip, required this.spent, required this.store,
  });
  final Trip trip;
  final Money? spent;
  final DemoStore store;
  @override
  Widget build(BuildContext context) {
    final double pct = (spent == null || trip.totalBudget.isZero)
        ? 0
        : (spent!.amountMinor / trip.totalBudget.amountMinor)
            .clamp(0.0, 1.0)
            .toDouble();
    final Color barColor = pct >= 0.98
        ? CmsColors.outflow
        : pct >= 0.85
            ? CmsColors.warning
            : CmsColors.accent;
    String leaderName;
    try {
      leaderName = store.userById(trip.leaderId).displayName;
    } catch (_) {
      leaderName = '—';
    }
    return InkWell(
      onTap: () => GoRouter.of(context).go('/cms/trips/${trip.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 36, height: 36,
              child: Container(
                decoration: BoxDecoration(
                  color: CmsColors.brandTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  trip.countryCode.toUpperCase(),
                  style: const TextStyle(
                    color: CmsColors.brand,
                    fontSize: 11, fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
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
                      fontSize: 13, fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${trip.countryName} · ${trip.currency} · '
                    'led by $leaderName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CmsColors.textSecondary, fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
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
                              : '${spent!.format()} of ${trip.totalBudget.format()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CmsColors.textBody,
                            fontSize: 11.5, fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Text(
                        '${(pct * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: barColor,
                          fontSize: 11, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: pct, minHeight: 4,
                      backgroundColor: CmsColors.bgElev,
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 3,
              ),
              decoration: BoxDecoration(
                color: trip.status == TripStatus.closed
                    ? CmsColors.bgElev
                    : CmsColors.accentSoft,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                trip.status.name.toUpperCase(),
                style: TextStyle(
                  color: trip.status == TripStatus.closed
                      ? CmsColors.textSecondary
                      : CmsColors.accentDeep,
                  fontSize: 10, fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.arrow_forward, size: 14, color: CmsColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SchedulesCard extends StatelessWidget {
  const _SchedulesCard({required this.tied});
  final List<ReportScheduleRow> tied;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CmsColors.surfaceCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: CmsColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: tied.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: <Widget>[
                    const Text(
                      'No scheduled deliveries for this mission yet.',
                      style: TextStyle(
                        color: CmsColors.textSecondary, fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () =>
                          GoRouter.of(context).go('/cms/reports'),
                      child: const Text('Create one in Reports'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: <Widget>[
                for (int i = 0; i < tied.length; i++) ...<Widget>[
                  if (i > 0)
                    const Divider(height: 1, color: CmsColors.divider),
                  _ScheduleRow(row: tied[i]),
                ],
              ],
            ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.row});
  final ReportScheduleRow row;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.schedule,
            size: 16,
            color: row.active ? CmsColors.brand : CmsColors.textTertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Daily mission rollup at '
              '${row.utcHour.toString().padLeft(2, '0')}:00 UTC '
              '· next ${DateFormat('MMM d HH:mm').format(row.nextRunAt.toLocal())}',
              style: const TextStyle(
                color: CmsColors.textBody, fontSize: 12,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: row.active ? CmsColors.accentSoft : CmsColors.bgElev,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              row.active ? 'ACTIVE' : 'PAUSED',
              style: TextStyle(
                color: row.active
                    ? CmsColors.accentDeep
                    : CmsColors.textSecondary,
                fontSize: 10, fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
