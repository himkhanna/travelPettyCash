import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/trip_status_chip.dart';
import '../application/trips_providers.dart';
import '../domain/trip.dart';

/// Out-of-inventory: "All Trips" drawer destination. Mirrors TripsHomeScreen
/// (screen-inventory #2) but lists every trip the current user belongs to —
/// active, draft, and closed — with a status chip on each row.
class AllTripsScreen extends ConsumerWidget {
  const AllTripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Trip>> tripsAsync = ref.watch(allTripsProvider);
    final AppLocalizations l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/m/trips'),
        ),
        title: Text(l.trips_allTrips_title),
      ),
      body: SafeArea(
        child: tripsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, _) => Center(child: Text('Error: $e')),
          data: (List<Trip> trips) {
            if (trips.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
                  child: Text(
                    l.trips_allTrips_empty,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
              );
            }
            // Sort: active first, then draft, then closed; within each group
            // newest first by createdAt.
            final List<Trip> sorted = <Trip>[...trips]..sort((Trip a, Trip b) {
                final int ra = _rank(a.status);
                final int rb = _rank(b.status);
                if (ra != rb) return ra.compareTo(rb);
                return b.createdAt.compareTo(a.createdAt);
              });
            return ListView.separated(
              padding: const EdgeInsetsDirectional.all(AppSpacing.md),
              itemCount: sorted.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (BuildContext context, int i) =>
                  _AllTripsRow(trip: sorted[i]),
            );
          },
        ),
      ),
    );
  }

  int _rank(TripStatus s) {
    switch (s) {
      case TripStatus.active:
        return 0;
      case TripStatus.draft:
        return 1;
      case TripStatus.closed:
        return 2;
    }
  }
}

class _AllTripsRow extends StatelessWidget {
  const _AllTripsRow({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceCard,
      borderRadius: const BorderRadius.all(AppRadii.card),
      child: InkWell(
        borderRadius: const BorderRadius.all(AppRadii.card),
        onTap: () => GoRouter.of(context).go('/m/trips/${trip.id}/dashboard'),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              _AvatarCircle(imageUrl: trip.imageUrl, countryCode: trip.countryCode),
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
              TripStatusChip(status: trip.status),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({required this.imageUrl, required this.countryCode});
  final String? imageUrl;
  final String countryCode;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      color: AppColors.cream,
      alignment: Alignment.center,
      child: Text(_flagFor(countryCode), style: const TextStyle(fontSize: 24)),
    );
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.cream,
        shape: BoxShape.circle,
      ),
      child: imageUrl == null || imageUrl!.isEmpty
          ? fallback
          : Image.network(
              imageUrl!,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }

  String _flagFor(String code) {
    if (code.length != 2) return '\u{1F3F3}';
    final int base = 0x1F1E6;
    final int a = code.toUpperCase().codeUnitAt(0) - 0x41 + base;
    final int b = code.toUpperCase().codeUnitAt(1) - 0x41 + base;
    return String.fromCharCodes(<int>[a, b]);
  }
}
