import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/domain/user.dart';
import '../../features/trips/application/trips_providers.dart';
import '../../features/trips/domain/trip.dart';
import 'offline_status_provider.dart';

/// Full-page "You are offline" surface shown at `/m/offline`. Every
/// non-Add-Expense mobile route redirects here while the device has no
/// connectivity (real or demo-toggled). The only escape hatches are:
///
///   - Add an expense (queues locally via the existing sync coordinator)
///   - Retry — re-checks connectivity and reroutes back if we're online
///
/// Reading any live data while offline would just serve stale cached
/// values that the user can't refresh, so we deliberately hide the
/// whole UI surface rather than render an incomplete dashboard.
class OfflineScreen extends ConsumerWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    final AsyncValue<List<Trip>> tripsAsync =
        ref.watch(activeTripsProvider);
    final Trip? targetTrip = tripsAsync.maybeWhen(
      data: (List<Trip> trips) => trips.isEmpty ? null : trips.first,
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Cloud-off icon in the brand colour, sized for impact.
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppColors.brandTint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.cloud_off_outlined,
                      size: 44,
                      color: AppColors.brand,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'You are offline',
                    textAlign: TextAlign.center,
                    style: AppTypography.geist(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Most of the app needs a connection to load the '
                    'latest trips, balances, and chat. While you are '
                    "offline, you can still log expenses — they'll "
                    'sync to the server once you are back online.',
                    textAlign: TextAlign.center,
                    style: AppTypography.geist(
                      fontSize: 13.5,
                      color: AppColors.ink3,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Primary action — Add Expense. Only enabled when we
                  // know which trip to scope the draft to.
                  FilledButton.icon(
                    onPressed: targetTrip == null
                        ? null
                        : () => GoRouter.of(context).go(
                              '/m/trips/${targetTrip.id}/expenses/new',
                            ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('ADD EXPENSE AS DRAFT'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: AppColors.bgCard,
                      minimumSize: const Size(double.infinity, 48),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Secondary action — retry connectivity. We just
                  // invalidate the provider; the stream re-checks and
                  // the redirect bounces back to the prior route if
                  // we're online again.
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.invalidate(offlineStatusProvider),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('CHECK AGAIN'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brand,
                      side: const BorderSide(color: AppColors.line),
                      minimumSize: const Size(double.infinity, 44),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  if (me != null) ...<Widget>[
                    const SizedBox(height: 18),
                    Text(
                      'Signed in as ${me.displayName} · ${_roleLabel(me.role)}',
                      textAlign: TextAlign.center,
                      style: AppTypography.geist(
                        fontSize: 11.5,
                        color: AppColors.ink4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _roleLabel(UserRole r) {
    switch (r) {
      case UserRole.member:
        return 'Team Member';
      case UserRole.leader:
        return 'Trip Leader';
      case UserRole.admin:
        return 'Admin';
      case UserRole.superAdmin:
        return 'Super Admin';
    }
  }
}
