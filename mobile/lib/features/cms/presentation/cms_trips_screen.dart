import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart' show AppRadii;
import '../../../core/api/hydration_service.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/money/money.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../expenses/application/expenses_providers.dart';
import '../../expenses/domain/expense.dart';
import '../../missions/application/mission_providers.dart';
import '../../missions/domain/mission.dart';
import '../../trips/domain/trip.dart';
import 'cms_dashboard.dart' show adminAllTripsProvider;
import 'create_trip_dialog.dart';
import 'widgets/cms_layout.dart';
import 'widgets/cms_theme.dart';

/// Dedicated "all trips" view reached from the Trips sidebar item. Same
/// columns as the dashboard's trips table (TRIP, MISSION, LEAD, BUDGET,
/// MEMBERS, OPEN, CREATED) but full width and unconstrained — the
/// dashboard's table is intentionally a quick scan; this one is the
/// canonical list.
class CmsTripsScreen extends ConsumerStatefulWidget {
  const CmsTripsScreen({super.key});

  @override
  ConsumerState<CmsTripsScreen> createState() => _CmsTripsScreenState();
}

class _CmsTripsScreenState extends ConsumerState<CmsTripsScreen> {
  TripStatus _filter = TripStatus.active;

  @override
  Widget build(BuildContext context) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    if (me == null ||
        (me.role != UserRole.admin && me.role != UserRole.superAdmin)) {
      return const CmsLayout(
        active: CmsNavItem.trips,
        title: 'Trips',
        child: Center(child: Text('Admin only.')),
      );
    }
    final AsyncValue<bool> hydration =
        ref.watch(authenticatedHydrationProvider);
    final AsyncValue<List<Trip>> tripsAsync =
        ref.watch(adminAllTripsProvider);
    final AsyncValue<List<Mission>> missionsAsync =
        ref.watch(missionsProvider);

    return CmsLayout(
      active: CmsNavItem.trips,
      title: 'Trips',
      titleSubtitle: 'Every active, draft, and closed delegation.',
      trailing: <Widget>[
        if (me.role == UserRole.admin)
          ElevatedButton.icon(
            onPressed: _openCreate,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New trip'),
            style: ElevatedButton.styleFrom(
              backgroundColor: CmsColors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
      child: hydration.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (bool _) => tripsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, _) => Center(child: Text('Error: $e')),
          data: (List<Trip> trips) {
            final Map<String, Mission> missionById = <String, Mission>{
              for (final Mission m in missionsAsync.valueOrNull ??
                  const <Mission>[])
                m.id: m,
            };
            final List<Trip> rows = trips
                .where((Trip t) => t.status == _filter)
                .toList()
              ..sort((Trip a, Trip b) => b.createdAt.compareTo(a.createdAt));
            return _Body(
              filter: _filter,
              onFilter: (TripStatus s) => setState(() => _filter = s),
              rows: rows,
              missionById: missionById,
              counts: <TripStatus, int>{
                TripStatus.active: trips
                    .where((Trip t) => t.status == TripStatus.active)
                    .length,
                TripStatus.draft: trips
                    .where((Trip t) => t.status == TripStatus.draft)
                    .length,
                TripStatus.closed: trips
                    .where((Trip t) => t.status == TripStatus.closed)
                    .length,
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _openCreate() async {
    final bool? created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) => const CreateTripDialog(),
    );
    if (created == true) {
      ref.invalidate(adminAllTripsProvider);
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.filter,
    required this.onFilter,
    required this.rows,
    required this.missionById,
    required this.counts,
  });
  final TripStatus filter;
  final ValueChanged<TripStatus> onFilter;
  final List<Trip> rows;
  final Map<String, Mission> missionById;
  final Map<TripStatus, int> counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DemoStore store = ref.read(demoStoreProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (final TripStatus s in TripStatus.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterChip(
                    label: _labelFor(s),
                    count: counts[s] ?? 0,
                    selected: filter == s,
                    onTap: () => onFilter(s),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: CmsColors.surfaceCard,
              borderRadius: const BorderRadius.all(AppRadii.card),
              border: Border.all(color: CmsColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            // LayoutBuilder + SizedBox(width) gives the inner Column a
            // BOUNDED width so its Row > Expanded children can lay out
            // correctly. The earlier ConstrainedBox(minWidth) inside a
            // horizontal SingleChildScrollView left the width unbounded,
            // which deadlocked Flutter's layout pass.
            child: LayoutBuilder(
              builder: (BuildContext _, BoxConstraints c) {
                const double minTableWidth = 1000.0;
                final double tableWidth =
                    c.maxWidth >= minTableWidth ? c.maxWidth : minTableWidth;
                final Widget table = SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: <Widget>[
                      _Header(),
                      for (int i = 0; i < rows.length; i++) ...<Widget>[
                        if (i > 0)
                          const Divider(
                            height: 1, color: CmsColors.divider,
                          ),
                        _Row(
                          trip: rows[i],
                          mission: rows[i].missionId == null
                              ? null
                              : missionById[rows[i].missionId!],
                          store: store,
                        ),
                      ],
                      if (rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              'No trips in this view.',
                              style: TextStyle(
                                color: CmsColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
                if (tableWidth <= c.maxWidth) return table;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: table,
                );
              },
            ),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CmsColors.brand : CmsColors.surfaceCard,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? CmsColors.brand : CmsColors.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color:
                      selected ? CmsColors.surfaceCard : CmsColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? CmsColors.surfaceCard.withValues(alpha: 0.2)
                      : CmsColors.bgElev,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected
                        ? CmsColors.surfaceCard
                        : CmsColors.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
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

class _Header extends StatelessWidget {
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
          SizedBox(width: 80, child: Text('TRIP', style: h())),
          Expanded(flex: 3, child: Text('', style: h())),
          Expanded(flex: 3, child: Text('MISSION', style: h())),
          Expanded(flex: 2, child: Text('LEAD', style: h())),
          Expanded(flex: 3, child: Text('BUDGET', style: h())),
          Expanded(flex: 2, child: Text('MEMBERS', style: h())),
          SizedBox(width: 90, child: Text('CREATED', style: h())),
          const SizedBox(width: 28),
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({
    required this.trip,
    required this.mission,
    required this.store,
  });
  final Trip trip;
  final Mission? mission;
  final DemoStore store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Per-trip spend — fetched on demand. The dashboard's aggregate
    // already pre-warms expenses; this falls back to a direct list call
    // if a user came straight to /cms/trips without visiting /cms first.
    final AsyncValue<List<Expense>> expensesAsync =
        ref.watch(tripExpensesProvider(trip.id));
    final Money? spent = expensesAsync.maybeWhen<Money?>(
      data: (List<Expense> list) {
        if (list.isEmpty) return Money.zero(trip.currency);
        return list.fold<Money>(
          Money.zero(trip.currency),
          (Money acc, Expense e) => acc + e.amount,
        );
      },
      orElse: () => null,
    );
    final double pct = (spent == null || trip.totalBudget.isZero)
        ? 0
        : (spent.amountMinor / trip.totalBudget.amountMinor)
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
      onTap: () => context.go('/cms/trips/${trip.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 80,
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
                  : Text(
                      mission!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CmsColors.textBody,
                        fontSize: 12,
                      ),
                    ),
            ),
            Expanded(
              flex: 2,
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
                              : '${_compact(spent.amountMinor)} / ${_compact(trip.totalBudget.amountMinor)} ${trip.currency}',
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
                      valueColor: AlwaysStoppedAnimation<Color>(budgetColor),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${trip.memberIds.length + 1} '
                'member${trip.memberIds.length == 0 ? '' : 's'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CmsColors.textBody,
                  fontSize: 12,
                ),
              ),
            ),
            SizedBox(
              width: 90,
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
              Icons.arrow_forward,
              size: 14,
              color: CmsColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

String _flag(String code) {
  if (code.length != 2) return '🏳';
  const int base = 0x1F1E6;
  final int a = code.toUpperCase().codeUnitAt(0) - 0x41 + base;
  final int b = code.toUpperCase().codeUnitAt(1) - 0x41 + base;
  return String.fromCharCodes(<int>[a, b]);
}

String _compact(int minor) =>
    NumberFormat.compact(locale: 'en').format(minor / 100.0);
