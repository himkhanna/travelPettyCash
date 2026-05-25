import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/home_bottom_nav.dart';
import '../../../shared/widgets/pdd_primitives.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../notifications/application/notifications_providers.dart';
import '../../notifications/domain/notification.dart';
import '../application/trips_providers.dart';
import '../domain/trip.dart';

/// Mobile "Trips" bottom-nav destination — strictly the trip lists, no
/// greeting / KPIs / activity feed. Home (`/m/trips`) keeps the rich
/// dashboard; this screen (`/m/all-trips`) is the focused list view.
class TripsListScreen extends ConsumerWidget {
  const TripsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
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
    final AsyncValue<List<Trip>> tripsAsync = ref.watch(_allMyTripsProvider);
    final List<AppNotification> notifs =
        ref.watch(myNotificationsProvider).valueOrNull ??
            const <AppNotification>[];
    final int unreadCount = notifs
        .where((AppNotification n) => n.state == NotificationState.unread)
        .length;

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      bottomNavigationBar: HomeBottomNav(
        currentLocation: '/m/all-trips',
        inboxBadge: unreadCount,
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
                .toList()
              ..sort((Trip a, Trip b) => b.createdAt.compareTo(a.createdAt));
            final List<Trip> upcoming = trips
                .where((Trip t) => t.status == TripStatus.draft)
                .toList()
              ..sort((Trip a, Trip b) => b.createdAt.compareTo(a.createdAt));
            final List<Trip> archived = trips
                .where((Trip t) => t.status == TripStatus.closed)
                .toList()
              ..sort((Trip a, Trip b) => b.createdAt.compareTo(a.createdAt));
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  PddTopBar(
                    user: null,
                    title: 'All trips',
                    subtitle: '${trips.length} total · '
                        '${active.length} active',
                  ),
                  if (trips.isEmpty)
                    _EmptyState()
                  else ...<Widget>[
                    if (active.isNotEmpty) ...<Widget>[
                      const PddSectionLabel(label: 'Active'),
                      for (final Trip t in active)
                        _TripRow(trip: t, notifs: notifs),
                    ],
                    if (upcoming.isNotEmpty) ...<Widget>[
                      const PddSectionLabel(label: 'Upcoming'),
                      for (final Trip t in upcoming)
                        _TripRow(trip: t, notifs: notifs),
                    ],
                    if (archived.isNotEmpty) ...<Widget>[
                      const PddSectionLabel(label: 'Archived'),
                      for (final Trip t in archived)
                        _TripRow(trip: t, notifs: notifs),
                    ],
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

/// Same fan-out the home screen uses — every trip the user participates
/// in, status-agnostic. Re-declared privately here so this screen doesn't
/// depend on trips_home_screen's library-private provider.
final FutureProvider<List<Trip>> _allMyTripsProvider =
    FutureProvider<List<Trip>>((Ref ref) async {
  final User? user = await ref.watch(currentUserProvider.future);
  if (user == null) return <Trip>[];
  return ref.read(tripRepositoryProvider).allTrips();
});

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
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
                    'No trips yet',
                    style: AppTypography.geist(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'When an admin assigns you to a trip it will show up here.',
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

class _TripRow extends StatelessWidget {
  const _TripRow({required this.trip, required this.notifs});
  final Trip trip;
  final List<AppNotification> notifs;
  @override
  Widget build(BuildContext context) {
    final int unread = notifs
        .where((AppNotification n) =>
            n.state == NotificationState.unread &&
            n.payload['tripId'] == trip.id)
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Material(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go('/m/trips/${trip.id}/dashboard'),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
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
                    _flag(trip.countryCode),
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        trip.name,
                        style: AppTypography.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${trip.countryName} · ${trip.currency} · '
                        '${_dates(trip)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.geist(
                          fontSize: 12,
                          color: AppColors.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unread > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3,
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
          ),
        ),
      ),
    );
  }

  String _flag(String code) {
    if (code.length != 2) return '🏳️';
    const int base = 0x1F1E6;
    final int a = code.toUpperCase().codeUnitAt(0) - 0x41 + base;
    final int b = code.toUpperCase().codeUnitAt(1) - 0x41 + base;
    return String.fromCharCodes(<int>[a, b]);
  }

  String _dates(Trip t) {
    final DateFormat fmt = DateFormat('MMM d, yyyy');
    if (t.closedAt != null) {
      return '${fmt.format(t.createdAt)} → ${fmt.format(t.closedAt!)}';
    }
    return 'From ${fmt.format(t.createdAt)}';
  }
}
