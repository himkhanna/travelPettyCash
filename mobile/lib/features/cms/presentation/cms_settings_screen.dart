import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart' show AppRadii, AppSpacing;
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import 'add_category_dialog.dart';
import 'widgets/cms_layout.dart';
import 'widgets/cms_theme.dart';

/// Admin/Super Admin "Settings" hub. Was a single Coming-soon item in the
/// sidebar; now collects the secondary management screens (Users, Audit
/// log, Expense categories) into one place so the sidebar doesn't grow
/// every time a small admin tool ships.
class CmsSettingsScreen extends ConsumerWidget {
  const CmsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    if (me == null ||
        (me.role != UserRole.admin && me.role != UserRole.superAdmin)) {
      return const CmsLayout(
        active: CmsNavItem.settings,
        title: 'Settings',
        child: Center(child: Text('Admin only.')),
      );
    }
    return CmsLayout(
      active: CmsNavItem.settings,
      title: 'Settings',
      titleSubtitle: 'Manage users, audit, categories and other admin tools.',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 60),
        child: LayoutBuilder(
          builder: (BuildContext _, BoxConstraints c) {
            final int cols = c.maxWidth >= 1100
                ? 3
                : c.maxWidth >= 720
                    ? 2
                    : 1;
            const double gap = 14;
            final double w = (c.maxWidth - (cols - 1) * gap) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                SizedBox(
                  width: w,
                  child: _SettingsCard(
                    icon: Icons.people_outline,
                    title: 'Users',
                    description:
                        'Add or edit operators, leaders, admins and the '
                        'Director General. Deactivate without losing '
                        'audit history.',
                    cta: 'Manage users',
                    onTap: () => context.go('/cms/users'),
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _SettingsCard(
                    icon: Icons.check_circle_outline,
                    title: 'Audit log',
                    description:
                        'Every financial mutation — allocations, transfers, '
                        'expenses, lifecycle events — in chronological order.',
                    cta: 'Open audit log',
                    onTap: () => context.go('/cms/audit'),
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _SettingsCard(
                    icon: Icons.category_outlined,
                    title: 'Expense categories',
                    description:
                        'Add custom expense categories beyond the default '
                        'eight. Categories cannot be hard-deleted once used.',
                    cta: 'Add category',
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (BuildContext _) => const AddCategoryDialog(),
                    ),
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _SettingsCard(
                    icon: Icons.schedule,
                    title: 'Report schedules',
                    description:
                        'Daily and recurring deliveries for trips and '
                        'missions. Sends a Report ready notification to '
                        'every admin at the configured UTC hour.',
                    cta: 'Open Reports',
                    onTap: () => context.go('/cms/reports'),
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _SettingsCard(
                    icon: Icons.account_balance_outlined,
                    title: 'Funding sources',
                    description:
                        'Court Office, External Affairs, and other funding '
                        'pools the delegations draw against.',
                    cta: 'Coming soon',
                    onTap: null,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _SettingsCard(
                    icon: Icons.draw_outlined,
                    title: 'Digital signature',
                    description:
                        'PKCS#11 key custody and PAdES signing pipeline for '
                        'the finance letter.',
                    cta: 'Coming soon',
                    onTap: null,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _SettingsCard(
                    icon: Icons.tune,
                    title: 'System preferences',
                    description:
                        'Default currency, locale fallbacks, idempotency '
                        'window, retention policy.',
                    cta: 'Coming soon',
                    onTap: null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.cta,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String description;
  final String cta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Material(
      color: CmsColors.surfaceCard,
      borderRadius: const BorderRadius.all(AppRadii.card),
      child: InkWell(
        borderRadius: const BorderRadius.all(AppRadii.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(AppRadii.card),
            border: Border.all(color: CmsColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: enabled
                          ? CmsColors.brandTint
                          : CmsColors.bgElev,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      size: 16,
                      color: enabled
                          ? CmsColors.brand
                          : CmsColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: enabled
                            ? CmsColors.textPrimary
                            : CmsColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                description,
                style: const TextStyle(
                  color: CmsColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Text(
                    cta,
                    style: TextStyle(
                      color: enabled
                          ? CmsColors.brand
                          : CmsColors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (enabled) ...<Widget>[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward,
                      size: 13,
                      color: CmsColors.brand,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
