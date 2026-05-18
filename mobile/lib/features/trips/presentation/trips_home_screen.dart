import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/api/hydration_service.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/home_bottom_nav.dart';
import '../../../shared/widgets/pdd_primitives.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
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
                    subtitle: _roleLabel(me?.role),
                    onNotifs: () => context.go('/m/notifications'),
                    hasNotif: hasUnread,
                  ),
                  // Global pending-funds banner — surfaces every pending
                  // allocation / transfer addressed to this user across all
                  // their trips so they don't have to drill into each one.
                  if (me != null)
                    _GlobalPendingBanner(meId: me.id, trips: active),
                  if (active.isEmpty) _NoActiveTripCard(),
                  // Active trips render as compact rows — same layout as
                  // Upcoming / Archived, with a tiny balance line added so
                  // the user can scan their money status without tapping
                  // through. Hero cards used to live here but pushed
                  // additional trips off-screen.
                  if (active.isNotEmpty) ...<Widget>[
                    const PddSectionLabel(label: 'Active'),
                    for (final Trip t in active)
                      _TripRowCompact(
                        trip: t,
                        notifs: notifs,
                        meId: me?.id,
                        meRole: me?.role,
                        showBalance: true,
                        onTap: () =>
                            context.go('/m/trips/${t.id}/dashboard'),
                      ),
                  ],
                  if (upcoming.isNotEmpty) ...<Widget>[
                    const PddSectionLabel(label: 'Upcoming'),
                    for (final Trip t in upcoming)
                      _TripRowCompact(
                        trip: t,
                        notifs: notifs,
                        onTap: () =>
                            context.go('/m/trips/${t.id}/dashboard'),
                      ),
                  ],
                  if (archived.isNotEmpty) ...<Widget>[
                    const PddSectionLabel(label: 'Archived'),
                    for (final Trip t in archived)
                      _TripRowCompact(
                        trip: t,
                        notifs: notifs,
                        onTap: () =>
                            context.go('/m/trips/${t.id}/dashboard'),
                      ),
                  ],
                ],
              ),
            );
          },
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

String _dateRangeLabel(Trip t) {
  final DateFormat fmt = DateFormat('MMM d, yyyy');
  if (t.closedAt != null) {
    return '${fmt.format(t.createdAt)} → ${fmt.format(t.closedAt!)}';
  }
  return 'From ${fmt.format(t.createdAt)}';
}

String _flagFor(String code) {
  if (code.length != 2) return '🏳️';
  const int base = 0x1F1E6;
  final int a = code.toUpperCase().codeUnitAt(0) - 0x41 + base;
  final int b = code.toUpperCase().codeUnitAt(1) - 0x41 + base;
  return String.fromCharCodes(<int>[a, b]);
}

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

// ────────────────────────────────────────────────────────────────────
// Compact trip row (Upcoming + Archived sections)
// ────────────────────────────────────────────────────────────────────

class _TripRowCompact extends ConsumerWidget {
  const _TripRowCompact({
    required this.trip,
    required this.notifs,
    required this.onTap,
    this.meId,
    this.meRole,
    this.showBalance = false,
  });
  final Trip trip;
  final List<AppNotification> notifs;
  final VoidCallback onTap;

  /// When set, used to scope the balance lookup (leader sees trip total,
  /// member sees their wallet). Falls back to the provider lookup below.
  final String? meId;
  final UserRole? meRole;

  /// Show a one-line balance hint inside the row (e.g. on Active trips).
  /// Off by default so Upcoming / Archived rows stay minimal.
  final bool showBalance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int unread = notifs
        .where((AppNotification n) =>
            n.state == NotificationState.unread &&
            n.payload['tripId'] == trip.id)
        .length;

    // Pending allocations + transfers to surface the "tap to accept" pill.
    final String effectiveMeId =
        meId ?? ref.watch(currentUserProvider).valueOrNull?.id ?? '';
    final int pendingCount = ref
            .watch(tripAllocationsProvider(trip.id))
            .maybeWhen<int>(
              data: (List<Allocation> all) => all
                  .where((Allocation a) =>
                      a.toUserId == effectiveMeId &&
                      a.status == AllocationStatus.pending)
                  .length,
              orElse: () => 0,
            ) +
        ref.watch(tripTransfersProvider(trip.id)).maybeWhen<int>(
              data: (List<Transfer> all) => all
                  .where((Transfer t) =>
                      t.toUserId == effectiveMeId &&
                      t.status == AllocationStatus.pending)
                  .length,
              orElse: () => 0,
            );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Material(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.bgInset,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _flagFor(trip.countryCode),
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  trip.name,
                                  style: AppTypography.geist(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (trip.status == TripStatus.closed) ...<Widget>[
                                const SizedBox(width: 8),
                                _Pill(
                                  label: 'Closed',
                                  color: AppColors.ink3,
                                ),
                              ],
                              if (trip.status == TripStatus.draft) ...<Widget>[
                                const SizedBox(width: 8),
                                _Pill(
                                  label: 'Upcoming',
                                  color: AppColors.amber,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${trip.countryName} · ${_dateRangeLabel(trip)}',
                            style: AppTypography.geist(
                              fontSize: 12,
                              color: AppColors.ink3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (unread > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$unread',
                          style: AppTypography.geist(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.bgCard,
                          ),
                        ),
                      ),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.ink3,
                      size: 20,
                    ),
                  ],
                ),
                if (showBalance) ...<Widget>[
                  const SizedBox(height: 8),
                  _BalanceLine(
                    trip: trip,
                    scope: meRole == UserRole.leader
                        ? BalanceScope.trip
                        : BalanceScope.me,
                  ),
                ],
                if (pendingCount > 0) ...<Widget>[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.amberSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 13,
                          color: AppColors.goldDeep,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$pendingCount pending '
                          '${pendingCount == 1 ? 'fund' : 'funds'} · tap to accept',
                          style: AppTypography.geist(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.goldDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One-line balance hint for an Active trip row on Home — no large amount,
/// no gradient card, just the available money + a slim spent bar.
class _BalanceLine extends ConsumerWidget {
  const _BalanceLine({required this.trip, required this.scope});
  final Trip trip;
  final BalanceScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TripBalances> async = ref.watch(
      tripBalancesProvider((tripId: trip.id, scope: scope)),
    );
    return async.when(
      loading: () => const SizedBox(height: 14),
      error: (Object _, __) => const SizedBox.shrink(),
      data: (TripBalances b) {
        final Money available = scope == BalanceScope.trip
            ? (b.totalBudget - b.totalSpent)
            : b.totalBalance;
        final Money received = scope == BalanceScope.trip
            ? b.totalBudget
            : b.totalBalance + b.totalSpent;
        final double pct = received.isZero
            ? 0
            : (b.totalSpent.amountMinor / received.amountMinor)
                .clamp(0.0, 1.0)
                .toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  scope == BalanceScope.trip ? 'Available' : 'Your balance',
                  style: AppTypography.geist(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink3,
                    letterSpacing: 0.06 * 10,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_amountOnly(available)} ${trip.currency}',
                  style: AppTypography.geistMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brand,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor: AppColors.brandTint,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.brand),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTypography.geist(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.04,
        ),
      ),
    );
  }
}
