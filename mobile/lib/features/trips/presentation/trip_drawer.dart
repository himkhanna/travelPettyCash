import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/dev_menu.dart';
import '../../../core/fake/demo_store.dart';
import '../../../core/fake/fake_config.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';

/// Slide-out menu per screen-inventory #4 (Member) and #31 (Leader).
/// Member drawer: Logout / All Trips / Notifications / Chat
/// Leader drawer: + Manage Funds (between All Trips and Notifications)
class TripDrawer extends ConsumerWidget {
  const TripDrawer({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? user = ref.watch(currentUserProvider).valueOrNull;
    final int unread = ref
        .read(demoStoreProvider)
        .unreadNotificationCount(user?.id ?? '', tripId: tripId);
    final bool leaderOrAdmin = user?.role == UserRole.leader ||
        user?.role == UserRole.admin;

    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.brandBrown,
                    child: Text(
                      _initials(user?.displayName ?? '?'),
                      style: const TextStyle(
                        color: AppColors.cream,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    user?.displayName ?? '—',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    _roleLabel(user?.role),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const Divider(),
            _DrawerItem(
              icon: Icons.logout,
              label: 'LOGOUT',
              onTap: () {
                ref.read(fakeConfigProvider).setRole(FakeRole.unset);
                context.go('/');
              },
            ),
            _DrawerItem(
              icon: Icons.flight_takeoff,
              label: 'ALL TRIPS',
              onTap: () => context.go('/m/trips'),
            ),
            if (leaderOrAdmin)
              _DrawerItem(
                icon: Icons.account_balance_wallet_outlined,
                label: 'MANAGE FUNDS',
                onTap: () => context.go('/m/trips/$tripId/manage-funds'),
              ),
            _DrawerItem(
              icon: Icons.notifications_outlined,
              label: 'NOTIFICATIONS',
              trailing: unread > 0 ? _Badge(count: unread) : null,
              onTap: () => context.go('/m/notifications'),
            ),
            _DrawerItem(
              icon: Icons.chat_bubble_outline,
              label: 'CHAT',
              onTap: () => context.go('/m/trips/$tripId/chat'),
            ),
            const Spacer(),
            _DrawerItem(
              icon: Icons.tune,
              label: 'DEMO CONTROLS',
              onTap: () {
                Navigator.of(context).pop();
                DevMenu.show(context);
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final List<String> parts = name.split(' ').where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String _roleLabel(UserRole? r) {
    switch (r) {
      case UserRole.member:
        return 'Team Member';
      case UserRole.leader:
        return 'Team Leader';
      case UserRole.admin:
        return 'Admin';
      case UserRole.superAdmin:
        return 'Director General';
      case null:
        return '';
    }
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.brandBrown),
      title: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          fontSize: 13,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: const BoxDecoration(
        color: AppColors.outflow,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12),
      ),
    );
  }
}
