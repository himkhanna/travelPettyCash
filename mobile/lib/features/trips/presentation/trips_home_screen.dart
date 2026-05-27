import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/api/hydration_service.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/home_bottom_nav.dart';
import '../../../shared/widgets/pdd_primitives.dart';
import '../../auth/application/auth_actions.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../chat/application/chat_providers.dart';
import '../../chat/domain/chat.dart';
import '../../funds/application/funds_providers.dart';
import '../../funds/domain/funding.dart';
import '../../notifications/application/notifications_providers.dart';
import '../../notifications/domain/notification.dart';
import '../application/trips_providers.dart';
import '../domain/trip.dart';

/// Home screen for the mobile-app audience (Members + Leaders).
///
/// Layout:
/// 1. [PddTopBar] — avatar + role subtitle + name + notifications bell.
/// 2. Global pending-funds banner (if any allocations / transfers wait).
/// 3. "Active" section with compact rows — flag, name, dates, slim
///    available-balance line + spent bar. No hero gradients.
/// 4. "Upcoming" section (DRAFT trips) with [_TripRowCompact] rows.
/// 5. "Archived" section (CLOSED trips) with [_TripRowCompact] rows.
///
/// Trip-scoped actions (Allocate / Add expense / Transfer / Team) used to
/// live here as a 4-tile grid, but they target whichever trip happens to be
/// first in the active list and were misleading when a user has multiple
/// active trips. Those actions are now reached *inside* a trip by tapping
/// the trip card: the dashboard surfaces an Allocate button for leaders +
/// the bottom nav (Expenses / Transfer) + the FAB (Add expense).
class TripsHomeScreen extends ConsumerWidget {
  const TripsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<User?> userAsync = ref.watch(currentUserProvider);
    final AsyncValue<List<Trip>> tripsAsync = ref.watch(_allMyTripsProvider);
    final User? me = userAsync.valueOrNull;
    // Trigger hydration on page-reload-with-stored-token as a side effect.
    ref.watch(authenticatedHydrationProvider);

    // Portal guard — admin/super-admin tokens land on the wrong portal.
    if (me != null &&
        me.role != UserRole.member &&
        me.role != UserRole.leader) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go('/wrong-portal?expected=webAdmin');
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Notifications stream — drives the bell's red dot and the per-trip
    // unread counts on compact rows below.
    final List<AppNotification> notifs =
        ref.watch(myNotificationsProvider).valueOrNull ??
            const <AppNotification>[];
    final bool hasUnread =
        notifs.any((AppNotification n) => n.state == NotificationState.unread);
    final int unreadCount = notifs
        .where((AppNotification n) => n.state == NotificationState.unread)
        .length;

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      bottomNavigationBar: HomeBottomNav(
        currentLocation: '/m/trips',
        inboxBadge: unreadCount,
        // Profile button on a trip is the only "profile" surface in
        // the current IA — fall back to the first active trip's profile.
        profileTripId: tripsAsync.maybeWhen(
          data: (List<Trip> trips) => trips
              .where((Trip t) => t.status == TripStatus.active)
              .firstOrNull
              ?.id,
          orElse: () => null,
        ),
      ),
      body: SafeArea(
        child: tripsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, _) => Center(child: Text('Error: $e')),
          data: (List<Trip> trips) {
            final List<Trip> active = trips
                .where((Trip t) => t.status == TripStatus.active)
                .toList();
            final List<Trip> upcoming = trips
                .where((Trip t) => t.status == TripStatus.draft)
                .toList();
            final List<Trip> archived = trips
                .where((Trip t) => t.status == TripStatus.closed)
                .toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  PddTopBar(
                    user: me,
                    subtitle: _greeting(me),
                    title: me?.displayName.split(' ').first ?? 'Welcome',
                    onNotifs: () => context.go('/m/notifications'),
                    hasNotif: hasUnread,
                    actions: <Widget>[
                      PddTopBarIconButton(
                        icon: Icons.logout,
                        tooltip: 'Sign out',
                        onTap: () => confirmAndSignOut(context, ref),
                      ),
                    ],
                  ),
                  // Hero summary card — role-aware. Member sees their
                  // combined wallet across active trips; Leader sees the
                  // team-wide trip totals they're responsible for.
                  if (me != null && active.isNotEmpty)
                    _HeroSummary(me: me, activeTrips: active),
                  // Quick-stats strip — at-a-glance counters.
                  if (me != null)
                    _QuickStatsStrip(
                      activeCount: active.length,
                      meId: me.id,
                      activeTrips: active,
                    ),
                  // Pending-funds banner — surfaces every pending allocation
                  // / transfer addressed to this user across all trips so
                  // they don't have to drill into each one.
                  if (me != null)
                    _GlobalPendingBanner(meId: me.id, trips: active),
                  // Quick-add expense — the single most common action on
                  // Home. Auto-routes into Add Expense scoped to the most
                  // recent active trip; falls back to the trip picker if
                  // no trip is active.
                  if (active.isNotEmpty)
                    _QuickAddExpenseCta(activeTrips: active),
                  // Recent activity feed — top 5 notifications, rendered
                  // compactly. "View all" jumps to the full inbox.
                  if (notifs.isNotEmpty)
                    _RecentActivityCard(
                      notifs: notifs.take(5).toList(),
                    ),
                  // Empty state — only when this user has no trips at all.
                  // Active/Upcoming/Archived trip rows have been moved to
                  // the dedicated Trips tab (/m/all-trips) — Home is a
                  // dashboard, not a trip list.
                  if (active.isEmpty && upcoming.isEmpty && archived.isEmpty)
                    _NoActiveTripCard(),
                  // "See all trips" footer when there *are* trips but
                  // we deliberately don't list them here.
                  if (active.isNotEmpty || upcoming.isNotEmpty ||
                      archived.isNotEmpty)
                    _SeeAllTripsFooter(
                      activeCount: active.length,
                      upcomingCount: upcoming.length,
                      archivedCount: archived.length,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Big tappable card on Home that opens Add Expense. With one active
/// trip we route straight in; with multiple actives we surface a bottom
/// sheet so the user picks the trip rather than guessing for them.
class _QuickAddExpenseCta extends StatelessWidget {
  const _QuickAddExpenseCta({required this.activeTrips});
  final List<Trip> activeTrips;

  Future<void> _onTap(BuildContext context) async {
    if (activeTrips.length == 1) {
      GoRouter.of(context).go(
        '/m/trips/${activeTrips.first.id}/expenses/new',
      );
      return;
    }
    final String? tripId = await showModalBottomSheet<String>(
      context: context,
      // Scroll-controlled so the sheet doesn't try to lay out as
      // `mainAxisSize.min` against an unbounded parent — that was
      // producing a bottom-overflow stripe when a user had 4+ active
      // trips.
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // Cap at 70% viewport so the sheet always leaves room above
            // for the user to dismiss by tapping the scrim.
            maxHeight: MediaQuery.of(sheet).size.height * 0.7,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Add expense to which trip?',
                textAlign: TextAlign.center,
                style: AppTypography.geist(
                  fontSize: 15, fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'You have ${activeTrips.length} active trips. Pick one.',
                textAlign: TextAlign.center,
                style: AppTypography.geist(
                  fontSize: 12, color: AppColors.ink3,
                ),
              ),
              const SizedBox(height: 14),
              for (final Trip t in activeTrips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: AppColors.bgElev,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(sheet).pop(t.id),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.brandTint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.flight_takeoff_outlined,
                                size: 16, color: AppColors.brand,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    t.name,
                                    style: AppTypography.geist(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${t.countryName} · ${t.currency}',
                                    style: AppTypography.geist(
                                      fontSize: 11.5,
                                      color: AppColors.ink3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 18, color: AppColors.ink3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(sheet).pop(),
                child: const Text('CANCEL'),
              ),
            ],
          ),
          ),
        ),
      ),
    );
    if (tripId == null) return;
    if (!context.mounted) return;
    GoRouter.of(context).go('/m/trips/$tripId/expenses/new');
  }

  @override
  Widget build(BuildContext context) {
    final String subtitle = activeTrips.length == 1
        ? 'Attach an invoice photo and log line items.'
        : 'Pick from ${activeTrips.length} active trips.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onTap(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.add,
                    color: AppColors.gold,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'Add an expense',
                        style: AppTypography.geist(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.bgCard,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.geist(
                          fontSize: 12,
                          color: AppColors.bgCard.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: AppColors.bgCard.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-of-Home pointer that gestures at the dedicated Trips screen
/// for users who want to browse trips. Keeps Home as a dashboard but
/// preserves a discoverable path to the full list.
class _SeeAllTripsFooter extends StatelessWidget {
  const _SeeAllTripsFooter({
    required this.activeCount,
    required this.upcomingCount,
    required this.archivedCount,
  });
  final int activeCount;
  final int upcomingCount;
  final int archivedCount;
  @override
  Widget build(BuildContext context) {
    final String summary = <String>[
      if (activeCount > 0) '$activeCount active',
      if (upcomingCount > 0) '$upcomingCount upcoming',
      if (archivedCount > 0) '$archivedCount archived',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => GoRouter.of(context).go('/m/all-trips'),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.brandTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.flight_takeoff_outlined,
                    size: 16,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'All your trips',
                        style: AppTypography.geist(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        style: AppTypography.geist(
                          fontSize: 11.5,
                          color: AppColors.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.ink3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compose the full visible trip set for this user — active, upcoming, and
/// archived — in one fetch. The repository's `activeTrips()` excludes
/// closed/draft entries so we hit `allTrips()` here and filter client-side.
final FutureProvider<List<Trip>> _allMyTripsProvider =
    FutureProvider<List<Trip>>((Ref ref) async {
  final User? user = await ref.watch(currentUserProvider.future);
  if (user == null) return <Trip>[];
  return ref.read(tripRepositoryProvider).allTrips();
});

String _roleLabel(UserRole? r) {
  switch (r) {
    case UserRole.member:
      return 'Team Member';
    case UserRole.leader:
      return 'Trip Leader';
    case UserRole.admin:
      return 'Court Office';
    case UserRole.superAdmin:
      return 'Director General';
    case null:
      return 'Welcome back';
  }
}

/// Money.format() includes the currency code; the home balance line lays
/// out the amount + currency separately, so strip the code here.
String _amountOnly(Money m) {
  final NumberFormat f = NumberFormat.decimalPattern('en_US');
  return f.format(m.amountMinor / 100.0);
}

// _dateRangeLabel / _flagFor previously powered the per-trip rows that
// have been moved to /m/all-trips. The corresponding helpers there
// (trips_list_screen.dart) own their own formatting now.

/// Aggregates pending allocations + transfers across every trip on Home, so
/// the user can see "you have N pending funds across trips" without drilling
/// into each one. Tapping jumps to the first trip that has pending items.
class _GlobalPendingBanner extends ConsumerWidget {
  const _GlobalPendingBanner({required this.meId, required this.trips});
  final String meId;
  final List<Trip> trips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int totalPending = 0;
    String? firstTripWithPending;
    for (final Trip t in trips) {
      final int allocCount = ref
              .watch(tripAllocationsProvider(t.id))
              .maybeWhen<int>(
                data: (List<Allocation> all) => all
                    .where((Allocation a) =>
                        a.toUserId == meId &&
                        a.status == AllocationStatus.pending)
                    .length,
                orElse: () => 0,
              ) +
          ref.watch(tripTransfersProvider(t.id)).maybeWhen<int>(
                data: (List<Transfer> all) => all
                    .where((Transfer x) =>
                        x.toUserId == meId &&
                        x.status == AllocationStatus.pending)
                    .length,
                orElse: () => 0,
              );
      if (allocCount > 0) {
        totalPending += allocCount;
        firstTripWithPending ??= t.id;
      }
    }
    if (totalPending == 0 || firstTripWithPending == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => GoRouter.of(context)
              .go('/m/trips/$firstTripWithPending/dashboard'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.amber.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.warning_amber_outlined,
                    size: 18,
                    color: AppColors.goldDeep,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '$totalPending pending '
                        '${totalPending == 1 ? "fund" : "funds"} waiting',
                        style: AppTypography.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.goldDeep,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to review and accept',
                        style: AppTypography.geist(
                          fontSize: 11,
                          color: AppColors.goldDeep,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.goldDeep,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoActiveTripCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.brandTint,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.flight_takeoff,
                color: AppColors.brand,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'No active trip',
                    style: AppTypography.geist(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Upcoming and archived trips will appear below.',
                    style: AppTypography.geist(
                      fontSize: 12,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// _TripRowCompact / _BalanceLine / _Pill removed when Home was
// converted to a dashboard. Trip rows live exclusively on /m/all-trips
// (TripsListScreen) now — that screen renders its own row widget.

// ────────────────────────────────────────────────────────────────────
// Home dashboard — hero summary + quick stats + recent activity
// ────────────────────────────────────────────────────────────────────

/// Greets the user with a time-of-day label so the subtitle on Home
/// doesn't read as the same "Welcome back" every visit.
String _greeting(User? me) {
  final int h = DateTime.now().hour;
  final String period = h < 5
      ? 'Good evening'
      : h < 12
          ? 'Good morning'
          : h < 17
              ? 'Good afternoon'
              : 'Good evening';
  final String role = _roleLabel(me?.role);
  return me == null ? period : '$period · $role';
}

/// Role-aware hero card sitting just under the top bar. Member sees their
/// combined wallet across active trips (per-currency stripes when the user
/// has trips in more than one currency). Leader sees the same totals AS
/// trip-wide so they can scan the budgets they're accountable for.
class _HeroSummary extends ConsumerWidget {
  const _HeroSummary({required this.me, required this.activeTrips});
  final User me;
  final List<Trip> activeTrips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isLeader = me.role == UserRole.leader;
    final BalanceScope scope =
        isLeader ? BalanceScope.trip : BalanceScope.me;

    // Sum balances per currency across the user's active trips.
    final Map<String, Money> availableByCurrency = <String, Money>{};
    final Map<String, Money> spentByCurrency = <String, Money>{};
    final Map<String, Money> committedByCurrency = <String, Money>{};
    bool anyLoading = false;
    for (final Trip t in activeTrips) {
      final AsyncValue<TripBalances> async = ref.watch(
        tripBalancesProvider((tripId: t.id, scope: scope)),
      );
      async.when(
        loading: () => anyLoading = true,
        error: (Object _, __) {},
        data: (TripBalances b) {
          final Money available = scope == BalanceScope.trip
              ? (b.totalBudget - b.totalSpent)
              : b.totalBalance;
          final Money committed = scope == BalanceScope.trip
              ? b.totalBudget
              : b.totalBalance + b.totalSpent;
          availableByCurrency.update(
            t.currency,
            (Money v) => v + available,
            ifAbsent: () => available,
          );
          spentByCurrency.update(
            t.currency,
            (Money v) => v + b.totalSpent,
            ifAbsent: () => b.totalSpent,
          );
          committedByCurrency.update(
            t.currency,
            (Money v) => v + committed,
            ifAbsent: () => committed,
          );
        },
      );
    }

    final String headline = isLeader ? 'Team budget available' : 'Your wallet';
    final String byline = isLeader
        ? 'Across ${activeTrips.length} trip${activeTrips.length == 1 ? '' : 's'} you lead'
        : 'Across ${activeTrips.length} active trip${activeTrips.length == 1 ? '' : 's'}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              AppColors.brandDeep,
              AppColors.brand,
              Color(0xFF155049),
            ],
            stops: <double>[0.0, 0.6, 1.0],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    headline,
                    style: AppTypography.geist(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.06 * 11,
                      color: AppColors.bgCard.withValues(alpha: 0.75),
                    ),
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.bgCard.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    isLeader
                        ? Icons.account_tree_outlined
                        : Icons.account_balance_wallet_outlined,
                    color: AppColors.bgCard,
                    size: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (anyLoading && availableByCurrency.isEmpty)
              SizedBox(
                height: 28,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: LinearProgressIndicator(
                    backgroundColor:
                        AppColors.bgCard.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.bgCard.withValues(alpha: 0.55),
                    ),
                    minHeight: 3,
                  ),
                ),
              )
            else
              _MultiCurrencyTotal(amounts: availableByCurrency),
            const SizedBox(height: 6),
            Text(
              byline,
              style: AppTypography.geist(
                fontSize: 11,
                color: AppColors.bgCard.withValues(alpha: 0.72),
              ),
            ),
            if (committedByCurrency.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              for (final MapEntry<String, Money> e
                  in committedByCurrency.entries)
                _HeroProgressLine(
                  currency: e.key,
                  spent: spentByCurrency[e.key] ??
                      Money.zero(e.key),
                  total: e.value,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders a multi-currency total inline (e.g. "SAR 4,250  ·  EGP 800").
/// When the user is single-currency this collapses to the standard
/// amount + ticker presentation.
class _MultiCurrencyTotal extends StatelessWidget {
  const _MultiCurrencyTotal({required this.amounts});
  final Map<String, Money> amounts;

  @override
  Widget build(BuildContext context) {
    if (amounts.isEmpty) {
      return Text(
        '—',
        style: AppTypography.geistMono(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.bgCard,
        ),
      );
    }
    final List<MapEntry<String, Money>> entries = amounts.entries.toList()
      ..sort(
        (MapEntry<String, Money> a, MapEntry<String, Money> b) =>
            b.value.amountMinor - a.value.amountMinor,
      );
    if (entries.length == 1) {
      final MapEntry<String, Money> e = entries.first;
      // FittedBox so a long amount (e.g. SAR 1,234,567.89) shrinks
      // gracefully on a narrow iPhone instead of overflowing the
      // gradient card right edge.
      return SizedBox(
        width: double.infinity,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: RichText(
            text: TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: _amountOnly(e.value),
                  style: AppTypography.geistMono(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.bgCard,
                    letterSpacing: -0.02 * 28,
                  ),
                ),
                TextSpan(
                  text: '  ${e.key}',
                  style: AppTypography.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.bgCard.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // Multi-currency — show top currency big, others as chips.
    final MapEntry<String, Money> first = entries.first;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 10,
      runSpacing: 4,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: RichText(
            text: TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: _amountOnly(first.value),
                  style: AppTypography.geistMono(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.bgCard,
                    letterSpacing: -0.02 * 26,
                  ),
                ),
                TextSpan(
                  text: '  ${first.key}',
                  style: AppTypography.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.bgCard.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final MapEntry<String, Money> e in entries.skip(1))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.bgCard.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${e.key} ${_amountOnly(e.value)}',
                style: AppTypography.geistMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.bgCard,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeroProgressLine extends StatelessWidget {
  const _HeroProgressLine({
    required this.currency,
    required this.spent,
    required this.total,
  });
  final String currency;
  final Money spent;
  final Money total;

  @override
  Widget build(BuildContext context) {
    final double pct = total.isZero
        ? 0.0
        : (spent.amountMinor / total.amountMinor).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                currency,
                style: AppTypography.geist(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.bgCard.withValues(alpha: 0.85),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_amountOnly(spent)} of ${_amountOnly(total)}',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.geistMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.bgCard.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: AppColors.bgCard.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Four-tile horizontal strip with at-a-glance counters under the hero
/// card: Active trips, Pending acceptances, Chats with unread, Unread
/// inbox. Each tile is tappable and routes to the corresponding screen
/// so Home doubles as a navigation hub.
class _QuickStatsStrip extends ConsumerWidget {
  const _QuickStatsStrip({
    required this.activeCount,
    required this.meId,
    required this.activeTrips,
  });
  final int activeCount;
  final String meId;
  final List<Trip> activeTrips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int pending = 0;
    for (final Trip t in activeTrips) {
      pending += ref.watch(tripAllocationsProvider(t.id)).maybeWhen<int>(
            data: (List<Allocation> all) => all
                .where((Allocation a) =>
                    a.toUserId == meId &&
                    a.status == AllocationStatus.pending)
                .length,
            orElse: () => 0,
          );
      pending += ref.watch(tripTransfersProvider(t.id)).maybeWhen<int>(
            data: (List<Transfer> all) => all
                .where((Transfer x) =>
                    x.toUserId == meId &&
                    x.status == AllocationStatus.pending)
                .length,
            orElse: () => 0,
          );
    }
    // Sum of per-thread unread badges across every chat the user is in.
    // allChatsProvider polls every 5s so this stays fresh as peers post.
    final int chatUnread = ref.watch(allChatsProvider).maybeWhen<int>(
          data: (List<ChatThread> threads) => threads.fold<int>(
            0,
            (int acc, ChatThread t) => acc + t.unreadCount,
          ),
          orElse: () => 0,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _StatTile(
              icon: Icons.flight_takeoff_outlined,
              label: 'Active',
              value: '$activeCount',
              accent: AppColors.brand,
              onTap: () => GoRouter.of(context).go('/m/all-trips'),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _StatTile(
              icon: Icons.hourglass_top_outlined,
              label: 'Pending',
              value: '$pending',
              accent: pending > 0 ? AppColors.amber : AppColors.ink3,
              onTap: activeTrips.isEmpty
                  ? null
                  : () => GoRouter.of(context)
                      .go('/m/trips/${activeTrips.first.id}/dashboard'),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _StatTile(
              icon: Icons.chat_bubble_outline,
              label: 'Chats',
              value: '$chatUnread',
              accent: chatUnread > 0 ? AppColors.brand : AppColors.ink3,
              onTap: () => GoRouter.of(context).go('/m/chat'),
            ),
          ),
          // "Unread" tile removed — duplicated the chat badge once chat
          // notifications were the bulk of inbox traffic, and the bell
          // icon in the top bar already shows the same count.
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget body = _content();
    if (onTap == null) return body;
    return Material(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: body,
      ),
    );
  }

  Widget _content() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 13, color: accent),
              ),
              const Spacer(),
              Text(
                value,
                style: AppTypography.geist(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink1,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label.toUpperCase(),
            style: AppTypography.geist(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.ink3,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact card showing the latest few notifications as a "recent activity"
/// feed. Pulls straight from notifications (the only audit-style source a
/// non-admin user can see).
class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.notifs});
  final List<AppNotification> notifs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(
                children: <Widget>[
                  Text(
                    'Recent activity',
                    style: AppTypography.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink1,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        GoRouter.of(context).go('/m/notifications'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      foregroundColor: AppColors.brand,
                    ),
                    child: Text(
                      'View all',
                      style: AppTypography.geist(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brand,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (int i = 0; i < notifs.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: 1, color: AppColors.line),
              _ActivityRow(n: notifs[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.n});
  final AppNotification n;

  @override
  Widget build(BuildContext context) {
    final ({Color color, IconData icon}) cfg = _styleFor(n.type);
    final bool unread = n.state == NotificationState.unread;
    return InkWell(
      onTap: () {
        final String? tripId = n.payload['tripId'] as String?;
        if (n.type == NotificationType.expenseQuery) {
          final String? expenseId = n.payload['expenseId'] as String?;
          if (tripId != null && expenseId != null) {
            GoRouter.of(context).go('/m/trips/$tripId/expenses/$expenseId');
            return;
          }
        }
        if (n.type == NotificationType.chatMessage) {
          final String? threadId = n.payload['threadId'] as String?;
          if (tripId != null && threadId != null) {
            GoRouter.of(context).go('/m/trips/$tripId/chat/$threadId');
            return;
          }
        }
        if (tripId != null) {
          GoRouter.of(context).go('/m/trips/$tripId/dashboard');
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: cfg.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Icon(cfg.icon, size: 13, color: cfg.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _summarize(n),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.geist(
                      fontSize: 12.5,
                      color: AppColors.ink1,
                      height: 1.3,
                      fontWeight:
                          unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _timeAgo(n.createdAt),
                    style: AppTypography.geist(
                      fontSize: 10.5,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                margin: const EdgeInsets.only(left: 6, top: 4),
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.red,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  ({Color color, IconData icon}) _styleFor(NotificationType t) {
    switch (t) {
      case NotificationType.allocationReceived:
        return (color: AppColors.gold, icon: Icons.account_balance_outlined);
      case NotificationType.transferReceived:
        return (color: AppColors.brand, icon: Icons.swap_horiz);
      case NotificationType.transferAccepted:
        return (color: AppColors.green, icon: Icons.check_circle_outline);
      case NotificationType.tripAssigned:
        return (color: AppColors.brand, icon: Icons.flight_outlined);
      case NotificationType.tripClosed:
        return (color: AppColors.ink3, icon: Icons.lock_outline);
      case NotificationType.expenseQuery:
        return (color: AppColors.amber, icon: Icons.help_outline);
      case NotificationType.reportReady:
        return (color: AppColors.brand, icon: Icons.description_outlined);
      case NotificationType.chatMessage:
        return (color: AppColors.brand, icon: Icons.chat_bubble_outline);
    }
  }

  String _summarize(AppNotification n) {
    switch (n.type) {
      case NotificationType.allocationReceived:
        return 'Funds allocated to you';
      case NotificationType.transferReceived:
        return 'You received a transfer';
      case NotificationType.transferAccepted:
        return n.payload['response'] == 'declined'
            ? 'Your transfer was declined'
            : 'Your transfer was accepted';
      case NotificationType.tripAssigned:
        return 'Added to a new trip';
      case NotificationType.tripClosed:
        return 'A trip you were on was closed';
      case NotificationType.expenseQuery:
        final String snip = (n.payload['snippet'] as String?) ?? '';
        return snip.isEmpty ? 'Comment on an expense' : 'Comment: "$snip"';
      case NotificationType.reportReady:
        final String tripName =
            (n.payload['tripName'] as String?) ?? 'a trip';
        return 'Report ready for $tripName';
      case NotificationType.chatMessage:
        final String tripName =
            (n.payload['tripName'] as String?) ?? 'a trip';
        final String snip = (n.payload['snippet'] as String?) ?? '';
        return snip.isEmpty
            ? 'New message in $tripName'
            : 'Chat in $tripName: "$snip"';
    }
  }

  String _timeAgo(DateTime at) {
    final Duration d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return DateFormat('d MMM').format(at);
  }
}
