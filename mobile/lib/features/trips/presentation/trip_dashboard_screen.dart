import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/dual_arc_donut.dart';
import '../../../shared/widgets/source_balance_card.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/sync_status_banner.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../../shared/widgets/trip_status_chip.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../application/trips_providers.dart';
import '../domain/trip.dart';
import 'trip_drawer.dart';

/// Screens #3 / #4 (Member) and #22 / #23 / #31 (Leader).
///
/// Members see "My View" only. Leaders and Admins see a top tab switcher
/// between "My View" (per-user balance) and "Trip View" (trip-wide rollup).
class TripDashboardScreen extends ConsumerStatefulWidget {
  const TripDashboardScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<TripDashboardScreen> createState() =>
      _TripDashboardScreenState();
}

class _TripDashboardScreenState extends ConsumerState<TripDashboardScreen> {
  BalanceScope _scope = BalanceScope.me;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Trip> tripAsync = ref.watch(
      tripDetailProvider(widget.tripId),
    );
    final User? user = ref.watch(currentUserProvider).valueOrNull;
    final bool leaderOrAdmin =
        user?.role == UserRole.leader ||
        user?.role == UserRole.admin ||
        user?.role == UserRole.superAdmin;

    final bool isClosed = tripAsync.maybeWhen(
      data: (Trip t) => t.status == TripStatus.closed,
      orElse: () => false,
    );

    return Scaffold(
      drawer: TripDrawer(tripId: widget.tripId),
      appBar: AppBar(
        title: tripAsync.maybeWhen(
          data: (Trip t) => Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(child: Text(t.countryName.toUpperCase())),
              if (t.status != TripStatus.active) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                TripStatusChip(status: t.status),
              ],
            ],
          ),
          orElse: () => const Text('Trip'),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.go('/m/trips'),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const SyncStatusBanner(),
            tripAsync.maybeWhen(
              data: (Trip t) => t.status == TripStatus.closed
                  ? _TripClosedBanner(closedAt: t.closedAt)
                  : const SizedBox.shrink(),
              orElse: () => const SizedBox.shrink(),
            ),
            if (leaderOrAdmin)
              _ScopeTabs(
                scope: _scope,
                onChanged: (BalanceScope s) => setState(() => _scope = s),
              ),
            Expanded(
              child: _DashboardBody(tripId: widget.tripId, scope: _scope),
            ),
          ],
        ),
      ),
      bottomNavigationBar: TripBottomNav(
        tripId: widget.tripId,
        currentLocation: GoRouterState.of(context).matchedLocation,
        tripClosed: isClosed,
      ),
    );
  }
}

class _TripClosedBanner extends StatelessWidget {
  const _TripClosedBanner({required this.closedAt});
  final DateTime? closedAt;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String date = closedAt == null ? '—' : _formatDate(closedAt!);
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.outflow.withValues(alpha: 0.08),
      child: Row(
        children: <Widget>[
          const Icon(Icons.lock_outline, size: 16, color: AppColors.outflow),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l.trip_closed_banner(date),
              style: const TextStyle(
                color: AppColors.outflow,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _ScopeTabs extends StatelessWidget {
  const _ScopeTabs({required this.scope, required this.onChanged});
  final BalanceScope scope;
  final ValueChanged<BalanceScope> onChanged;

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
            label: 'MY VIEW',
            active: scope == BalanceScope.me,
            onTap: () => onChanged(BalanceScope.me),
          ),
          _Tab(
            label: 'TRIP VIEW',
            active: scope == BalanceScope.trip,
            onTap: () => onChanged(BalanceScope.trip),
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

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.tripId, required this.scope});
  final String tripId;
  final BalanceScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TripBalances> balances = ref.watch(
      tripBalancesProvider((tripId: tripId, scope: scope)),
    );

    return balances.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => Center(child: Text('Error: $e')),
      data: (TripBalances b) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            Center(
              child: DualArcDonut(balance: b.totalBalance, spent: b.totalSpent),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final SourceBalance s in b.perSource) ...<Widget>[
              SourceBalanceCard(balance: s),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.md),
            _TotalBudgetPill(
              amount: scope == BalanceScope.trip
                  ? b.totalBudget
                  : _sumReceived(b),
            ),
          ],
        ),
      ),
    );
  }

  Money _sumReceived(TripBalances b) => b.perSource.fold(
    Money.zero(b.totalBudget.currencyCode),
    (Money a, SourceBalance s) => a + s.received,
  );
}

class _TotalBudgetPill extends StatelessWidget {
  const _TotalBudgetPill({required this.amount});
  final Money amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandBrown,
        borderRadius: const BorderRadius.all(AppRadii.button),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            'TOTAL TRIP BUDGET',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.cream,
              letterSpacing: 1.4,
            ),
          ),
          Text(
            amount.format(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.cream,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

