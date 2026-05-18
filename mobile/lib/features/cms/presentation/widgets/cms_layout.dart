import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme.dart';
import '../../../../shared/widgets/language_toggle_button.dart';
import '../../../auth/application/auth_providers.dart';
import '../../../auth/domain/user.dart';

/// Top-level CMS sections — each maps to a route.
enum CmsNavItem { dashboard, users, audit, dg }

extension on CmsNavItem {
  String get label {
    switch (this) {
      case CmsNavItem.dashboard:
        return 'Dashboard';
      case CmsNavItem.users:
        return 'Users';
      case CmsNavItem.audit:
        return 'Audit';
      case CmsNavItem.dg:
        return 'DG View';
    }
  }

  String get path {
    switch (this) {
      case CmsNavItem.dashboard:
        return '/cms';
      case CmsNavItem.users:
        return '/cms/users';
      case CmsNavItem.audit:
        return '/cms/audit';
      case CmsNavItem.dg:
        return '/cms/dg';
    }
  }
}

/// Shared shell for every CMS screen. Renders a government-style header
/// (PDD wordmark on the left, top nav in the middle, language toggle +
/// account avatar on the right) above the screen body. Mirrors the layout
/// pattern on www.protocol.dubai.ae so the in-app console feels native to
/// the same family of Protocol Department web properties.
class CmsLayout extends ConsumerWidget {
  const CmsLayout({
    super.key,
    required this.active,
    required this.child,
    this.floatingActionButton,
    this.trailing,
  });

  final CmsNavItem active;
  final Widget child;
  final Widget? floatingActionButton;

  /// Optional widgets to render between the nav menu and the language
  /// toggle — used for context-aware actions like "Add Category" on the
  /// dashboard or "Reports" on a selected trip.
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: <Widget>[
          _GovStrip(),
          _MainHeader(active: active, me: me, trailing: trailing),
          Expanded(child: child),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Slim dark strip above the main header — mirrors the "Government of
/// Dubai" wordmark band on protocol.dubai.ae and other Dubai government
/// portals. Holds the bilingual wordmark + a tiny meta line.
class _GovStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: AppColors.brandBrownDark,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: <Widget>[
          Text(
            'GOVERNMENT OF DUBAI · حكومة دبي',
            style: TextStyle(
              color: AppColors.cream.withValues(alpha: 0.92),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          Text(
            'Protocol Department · Internal',
            style: TextStyle(
              color: AppColors.cream.withValues(alpha: 0.7),
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _MainHeader extends StatelessWidget {
  const _MainHeader({
    required this.active,
    required this.me,
    required this.trailing,
  });

  final CmsNavItem active;
  final User? me;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final bool isSuperAdmin = me?.role == UserRole.superAdmin;
    final List<CmsNavItem> items = <CmsNavItem>[
      CmsNavItem.dashboard,
      CmsNavItem.users,
      CmsNavItem.audit,
      if (isSuperAdmin) CmsNavItem.dg,
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      height: 72,
      child: Row(
        children: <Widget>[
          // Logo + wordmark
          const _PddLogo(),
          const SizedBox(width: AppSpacing.xl),
          // Top nav menu
          for (final CmsNavItem item in items)
            _NavItem(
              item: item,
              active: active == item,
              onTap: () => GoRouter.of(context).go(item.path),
            ),
          const Spacer(),
          // Context-aware actions (Add Category, Reports, etc.)
          if (trailing != null) ...trailing!,
          if (trailing != null && trailing!.isNotEmpty)
            const SizedBox(width: AppSpacing.sm),
          // Language toggle
          const LanguageToggleButton(),
          const SizedBox(width: AppSpacing.sm),
          // Account dropdown
          if (me != null) _AccountMenu(me: me!),
        ],
      ),
    );
  }
}

class _PddLogo extends StatelessWidget {
  const _PddLogo();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => GoRouter.of(context).go('/cms'),
      borderRadius: const BorderRadius.all(AppRadii.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Falcon emblem stand-in. Real SVG drops in here later — for
            // now a layered icon set reads as a government crest at a glance.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.brandBrown,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.shield_outlined,
                color: AppColors.cream,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'PDD Delegation Expenses',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.brandBrownDark,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                Text(
                  'صرفيات الوفود الرسمية',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final CmsNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.brandBrown : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          item.label.toUpperCase(),
          style: TextStyle(
            color: active ? AppColors.brandBrown : AppColors.textSecondary,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            fontSize: 13,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.me});

  final User me;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.brandBrown,
              child: Text(
                _initials(me.displayName),
                style: const TextStyle(
                  color: AppColors.cream,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  me.displayName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.1,
                  ),
                ),
                Text(
                  _roleLabel(me.role),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
      itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Text(me.email, style: const TextStyle(color: AppColors.textSecondary)),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'signout',
          child: ListTile(
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      onSelected: (String v) {
        if (v == 'signout') GoRouter.of(context).go('/');
      },
    );
  }

  String _initials(String name) {
    final List<String> parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String _roleLabel(UserRole r) {
    switch (r) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.superAdmin:
        return 'Director General';
      case UserRole.leader:
        return 'Leader';
      case UserRole.member:
        return 'Member';
    }
  }
}
