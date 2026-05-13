import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/dev_menu.dart';
import '../../../core/fake/demo_store.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../application/trips_providers.dart';
import '../domain/trip.dart';

/// Screen-inventory #2 / #17 — Active Trips home.
class TripsHomeScreen extends ConsumerWidget {
  const TripsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<User?> userAsync = ref.watch(currentUserProvider);
    final AsyncValue<List<Trip>> tripsAsync = ref.watch(activeTripsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const _AppBarTitle(),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Demo controls',
            onPressed: () => DevMenu.show(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              userAsync.when(
                data: (User? u) => _Greeting(user: u),
                loading: () => const _Greeting(user: null),
                error: (Object e, _) => Text('Error: $e'),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'ACTIVE TRIPS',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: tripsAsync.when(
                  data: (List<Trip> trips) => trips.isEmpty
                      ? const _EmptyState()
                      : _TripList(trips: trips),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (Object e, _) => Center(child: Text('Error: $e')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.brandBrown,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.flight, size: 16, color: AppColors.cream),
        ),
        const SizedBox(width: AppSpacing.sm),
        const Text('PDD Petty Cash'),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.user});
  final User? user;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'HELLO',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            letterSpacing: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          (user?.displayName ?? 'DEMO USER').toUpperCase(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.flight_takeoff, size: 48, color: AppColors.goldOlive),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No active trips for this role.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TripList extends ConsumerWidget {
  const _TripList({required this.trips});
  final List<Trip> trips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      itemCount: trips.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (BuildContext context, int i) {
        final Trip t = trips[i];
        final String me = ref.read(currentUserProvider).valueOrNull?.id ?? '';
        final int unread = ref
            .read(demoStoreProvider)
            .unreadNotificationCount(me, tripId: t.id);
        return _TripCard(
          trip: t,
          unread: unread,
          onTap: () => context.go('/m/trips/${t.id}/dashboard'),
        );
      },
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.unread,
    required this.onTap,
  });
  final Trip trip;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceCard,
      borderRadius: const BorderRadius.all(AppRadii.card),
      child: InkWell(
        borderRadius: const BorderRadius.all(AppRadii.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              _FlagCircle(countryCode: trip.countryCode),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      trip.countryName.toUpperCase(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trip.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread > 0) _UnreadBadge(count: unread),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlagCircle extends StatelessWidget {
  const _FlagCircle({required this.countryCode});
  final String countryCode;

  @override
  Widget build(BuildContext context) {
    final String emoji = _flagFor(countryCode);
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.cream,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 26)),
    );
  }

  String _flagFor(String code) {
    if (code.length != 2) return '🏳️';
    final int base = 0x1F1E6;
    final int a = code.toUpperCase().codeUnitAt(0) - 0x41 + base;
    final int b = code.toUpperCase().codeUnitAt(1) - 0x41 + base;
    return String.fromCharCodes(<int>[a, b]);
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const BoxDecoration(
        color: AppColors.outflow,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}
