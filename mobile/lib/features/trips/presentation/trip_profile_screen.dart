import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/pdd_primitives.dart';
import '../../../shared/widgets/trip_bottom_nav.dart';
import '../../auth/application/auth_actions.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';

/// Profile screen per the handoff (`app.jsx → ProfileScreen`).
/// Large centered avatar + name + ID, followed by a menu list (Digital
/// signature · Notifications · Chat · Preferences) and a version footer.
class TripProfileScreen extends ConsumerWidget {
  const TripProfileScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      bottomNavigationBar: TripBottomNav(
        tripId: tripId,
        currentLocation: GoRouterState.of(context).matchedLocation,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            PddTopBar(
              user: me,
              leadingBack: true,
              onBack: () => context.go('/m/trips/$tripId/dashboard'),
              title: 'Profile',
              subtitle: _roleLabel(me?.role),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: 12),
                    Center(child: PddAvatar(user: me, size: 96)),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        me?.displayName ?? 'Unknown',
                        style: AppTypography.geist(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.02 * 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        '@${me?.username ?? "—"} · ${_roleLabel(me?.role)}',
                        style: AppTypography.geist(
                          fontSize: 13,
                          color: AppColors.ink3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _MenuList(items: <_MenuItem>[
                      _MenuItem(
                        icon: Icons.draw_outlined,
                        label: 'Digital signature',
                        trailing: 'Configured',
                        onTap: () => showPddToast(
                          context,
                          'Signature capture lands in Milestone E.',
                          info: true,
                        ),
                      ),
                      _MenuItem(
                        icon: Icons.notifications_none_outlined,
                        label: 'Notifications',
                        onTap: () => context.go('/m/notifications'),
                      ),
                      _MenuItem(
                        icon: Icons.chat_bubble_outline,
                        label: 'Chat',
                        onTap: () => context.go('/m/chat'),
                      ),
                      _MenuItem(
                        icon: Icons.settings_outlined,
                        label: 'Preferences',
                        onTap: () => showPddToast(
                          context,
                          'Preferences not yet implemented.',
                          info: true,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _MenuList(items: <_MenuItem>[
                      _MenuItem(
                        icon: Icons.logout,
                        label: 'Sign out',
                        destructive: true,
                        onTap: () => confirmAndSignOut(context, ref),
                      ),
                    ]),
                    const SizedBox(height: 22),
                    Center(
                      child: Text(
                        'PDD Delegation Expenses · v0.1.0',
                        style: AppTypography.geist(
                          fontSize: 11,
                          color: AppColors.ink3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
        return '';
    }
  }
}

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;
  final bool destructive;
}

class _MenuList extends StatelessWidget {
  const _MenuList({required this.items});
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0)
              const Divider(height: 1, color: AppColors.line),
            InkWell(
              onTap: items[i].onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: items[i].destructive
                            ? AppColors.redSoft
                            : AppColors.brandTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        items[i].icon,
                        size: 18,
                        color: items[i].destructive
                            ? AppColors.red
                            : AppColors.brand,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        items[i].label,
                        style: AppTypography.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: items[i].destructive
                              ? AppColors.red
                              : AppColors.ink1,
                        ),
                      ),
                    ),
                    if (items[i].trailing != null) ...<Widget>[
                      Text(
                        items[i].trailing!,
                        style: AppTypography.geist(
                          fontSize: 12,
                          color: AppColors.ink3,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    const Icon(Icons.chevron_right,
                        color: AppColors.ink3, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
