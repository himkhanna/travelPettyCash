import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';

/// Top-level bottom nav for the mobile *landing* (trips list).
///
/// Trip-scoped actions (Add expense / Transfer / etc.) need a specific
/// trip, so they live on {@link TripBottomNav} inside a trip. This nav
/// is for everything else a user can do from the landing surface:
///
///   Home · Inbox · Trips · Profile
///
/// Profile maps to the most-recently-active trip's profile if one exists,
/// otherwise to a placeholder route — Members + Leaders only ever have a
/// profile scoped to a trip in the current information architecture, so
/// the landing reuses the first active trip's profile screen.
class HomeBottomNav extends StatelessWidget {
  const HomeBottomNav({
    super.key,
    required this.currentLocation,
    this.inboxBadge = 0,
    this.profileTripId,
  });

  final String currentLocation;
  final int inboxBadge;
  final String? profileTripId;

  @override
  Widget build(BuildContext context) {
    final bool onHome = currentLocation == '/m/trips';
    final bool onAllTrips = currentLocation == '/m/all-trips';
    final bool onInbox = currentLocation.startsWith('/m/notifications');
    final bool onProfile = currentLocation.contains('/profile');

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _NavItem(
                icon: Icons.home_outlined,
                label: 'Home',
                active: onHome,
                onTap: () => context.go('/m/trips'),
              ),
              _NavItem(
                icon: Icons.notifications_none_outlined,
                label: 'Inbox',
                active: onInbox,
                badgeCount: inboxBadge,
                onTap: () => context.go('/m/notifications'),
              ),
              _NavItem(
                icon: Icons.flight_takeoff_outlined,
                label: 'Trips',
                active: onAllTrips,
                onTap: () => context.go('/m/all-trips'),
              ),
              _NavItem(
                icon: Icons.account_circle_outlined,
                label: 'Profile',
                active: onProfile,
                onTap: () {
                  if (profileTripId != null) {
                    context.go('/m/trips/$profileTripId/profile');
                  } else {
                    // No active trip — fall back to Home; the drawer
                    // surfaces logout / language toggle from any screen.
                    context.go('/m/trips');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? AppColors.brandBrown : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Icon(icon, color: color, size: 22),
                if (badgeCount > 0)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.outflow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(minWidth: 14),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
