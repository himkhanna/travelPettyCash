import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';

/// Five-item bottom nav per CLAUDE.md §8:
/// Dashboard · Expenses · Add (+) · Transfer · Profile
///
/// The Add slot is a raised FAB-style button that routes to a full screen,
/// not a tab swap (per screen-inventory #5).
class TripBottomNav extends StatelessWidget {
  const TripBottomNav({
    super.key,
    required this.tripId,
    required this.currentLocation,
  });

  final String tripId;
  final String currentLocation;

  @override
  Widget build(BuildContext context) {
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
                icon: Icons.donut_large_outlined,
                label: 'Home',
                active: currentLocation.endsWith('/dashboard'),
                onTap: () => context.go('/m/trips/$tripId/dashboard'),
              ),
              _NavItem(
                icon: Icons.receipt_long_outlined,
                label: 'Expenses',
                active: currentLocation.contains('/expenses/mine'),
                onTap: () => context.go('/m/trips/$tripId/expenses/mine'),
              ),
              _AddFab(onTap: () => context.go('/m/trips/$tripId/expenses/new')),
              _NavItem(
                icon: Icons.swap_horiz,
                label: 'Transfer',
                active: currentLocation.contains('/transfer'),
                onTap: () => context.go('/m/trips/$tripId/transfer'),
              ),
              _NavItem(
                icon: Icons.account_circle_outlined,
                label: 'Profile',
                active: currentLocation.contains('/profile'),
                onTap: () => context.go('/m/trips/$tripId/profile'),
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
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? AppColors.brandBrown : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: color, size: 22),
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

class _AddFab extends StatelessWidget {
  const _AddFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Center(
        child: Material(
          color: AppColors.brandBrown,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const SizedBox(
              width: 52,
              height: 52,
              child: Icon(Icons.add, color: AppColors.cream, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
