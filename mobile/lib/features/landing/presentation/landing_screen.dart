import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/fake_config.dart';

/// Landing page at "/" — picks a role and routes into either the mobile UI
/// (rendered inside a phone frame) or the CMS web UI.
class LandingScreen extends ConsumerWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FakeConfig cfg = ref.watch(fakeConfigProvider);

    return Scaffold(
      backgroundColor: AppColors.brandBrownDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _LandingHeader(),
                  const SizedBox(height: AppSpacing.xl),
                  _SectionLabel(text: 'Mobile App'.toUpperCase()),
                  const SizedBox(height: AppSpacing.md),
                  _RoleGrid(
                    onPick: (FakeRole r) {
                      cfg.setRole(r);
                      context.go('/m/trips');
                    },
                    roles: const <FakeRole>[
                      FakeRole.member,
                      FakeRole.leader,
                      FakeRole.admin,
                      FakeRole.superAdmin,
                    ],
                    target: _RoleTarget.mobile,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _SectionLabel(text: 'Admin Console (Web)'.toUpperCase()),
                  const SizedBox(height: AppSpacing.md),
                  _RoleGrid(
                    onPick: (FakeRole r) {
                      cfg.setRole(r);
                      context.go('/cms');
                    },
                    roles: const <FakeRole>[
                      FakeRole.admin,
                      FakeRole.superAdmin,
                    ],
                    target: _RoleTarget.cms,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _DemoNotice(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LandingHeader extends StatelessWidget {
  const _LandingHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'PDD Petty Cash',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: AppColors.cream,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Demo Console — pick a role to enter the prototype',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.cream.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: AppColors.goldOlive,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

enum _RoleTarget { mobile, cms }

class _RoleGrid extends StatelessWidget {
  const _RoleGrid({
    required this.roles,
    required this.onPick,
    required this.target,
  });

  final List<FakeRole> roles;
  final ValueChanged<FakeRole> onPick;
  final _RoleTarget target;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: <Widget>[
        for (final FakeRole r in roles)
          _RoleCard(role: r, target: target, onTap: () => onPick(r)),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.target,
    required this.onTap,
  });
  final FakeRole role;
  final _RoleTarget target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Material(
        color: AppColors.cream,
        borderRadius: const BorderRadius.all(AppRadii.card),
        child: InkWell(
          borderRadius: const BorderRadius.all(AppRadii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(_iconFor(role), color: AppColors.brandBrown, size: 32),
                const SizedBox(height: AppSpacing.md),
                Text(
                  _roleLabel(role),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _seedNameFor(role),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  target == _RoleTarget.mobile
                      ? 'Mobile UI →'
                      : 'Admin Console →',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.brandBrown,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(FakeRole r) {
    switch (r) {
      case FakeRole.member:
        return Icons.person_outline;
      case FakeRole.leader:
        return Icons.workspace_premium_outlined;
      case FakeRole.admin:
        return Icons.admin_panel_settings_outlined;
      case FakeRole.superAdmin:
        return Icons.shield_outlined;
      case FakeRole.unset:
        return Icons.help_outline;
    }
  }

  String _roleLabel(FakeRole r) {
    switch (r) {
      case FakeRole.member:
        return 'Team Member';
      case FakeRole.leader:
        return 'Team Leader';
      case FakeRole.admin:
        return 'Admin';
      case FakeRole.superAdmin:
        return 'Director General';
      case FakeRole.unset:
        return '';
    }
  }

  String _seedNameFor(FakeRole r) {
    switch (r) {
      case FakeRole.member:
        return 'Ahmed Al Maktoum';
      case FakeRole.leader:
        return 'Fatima Al Hashimi';
      case FakeRole.admin:
        return 'Khalid Al Suwaidi';
      case FakeRole.superAdmin:
        return 'Noura Al Falasi';
      case FakeRole.unset:
        return '';
    }
  }
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: AppColors.goldOlive.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, color: AppColors.goldOlive),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'This is a UI prototype against mocked data. '
              'No real funds, no real authentication. '
              'Use the Demo Controls menu inside the app to simulate offline mode, latency, and failures.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.cream,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
