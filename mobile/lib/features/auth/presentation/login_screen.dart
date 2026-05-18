import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/fake/fake_config.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/auth_providers.dart';
import '../data/auth_repository.dart';
import '../domain/user.dart';

/// Screen-inventory #1 — Login.
///
/// Two SSO buttons are mocked. UAE Pass routes the demo as a Member, PDD SSO
/// routes as a Leader, so reviewers can preview both seed accounts without
/// touching the dev menu. The real implementation (Spring Authorization Server
/// or UAE Pass OIDC) lands once §16 of CLAUDE.md is resolved.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.brandBrownDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: AppSpacing.xl),
                  const _FalconEmblem(),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    l.auth_login_title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: AppColors.cream,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l.appTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.goldOlive,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _SsoButton(
                    label: l.auth_login_uaePass,
                    background: AppColors.goldOlive,
                    foreground: AppColors.brandBrownDark,
                    icon: Icons.verified_user_outlined,
                    onPressed: _busy
                        ? null
                        : () => _signIn(UserRole.member, l),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _SsoButton(
                    label: l.auth_login_pddSso,
                    background: Colors.transparent,
                    foreground: AppColors.cream,
                    border: AppColors.cream,
                    icon: Icons.account_balance_outlined,
                    onPressed: _busy
                        ? null
                        : () => _signIn(UserRole.leader, l),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Align(
                    child: TextButton(
                      onPressed: _busy ? null : () => context.go('/forgot-password'),
                      child: Text(
                        l.auth_login_forgot,
                        style: const TextStyle(
                          color: AppColors.cream,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.cream,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    l.auth_login_demoNotice,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.cream.withValues(alpha: 0.7),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn(UserRole role, AppLocalizations l) async {
    setState(() => _busy = true);
    try {
      // Mock SSO latency.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final AuthRepository repo = ref.read(authRepositoryProvider);
      await repo.loginAsRole(role);
      if (!mounted) return;
      context.go('/m/trips');
    } catch (e) {
      // Fall back to setting the FakeConfig role directly so the demo always
      // proceeds even if a seed user is missing.
      ref.read(fakeConfigProvider).setRole(_fakeRoleFor(role));
      if (!mounted) return;
      context.go('/m/trips');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  FakeRole _fakeRoleFor(UserRole r) {
    switch (r) {
      case UserRole.member:
        return FakeRole.member;
      case UserRole.leader:
        return FakeRole.leader;
      case UserRole.admin:
        return FakeRole.admin;
      case UserRole.superAdmin:
        return FakeRole.superAdmin;
    }
  }
}

class _FalconEmblem extends StatelessWidget {
  const _FalconEmblem();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: AppColors.cream.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.goldOlive, width: 2),
        ),
        alignment: Alignment.center,
        // Placeholder for the falcon emblem — the final asset arrives with
        // the branding package from PDD (CLAUDE.md §8).
        child: const Icon(
          Icons.shield_moon_outlined,
          color: AppColors.goldOlive,
          size: 48,
        ),
      ),
    );
  }
}

class _SsoButton extends StatelessWidget {
  const _SsoButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.onPressed,
    this.border,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(AppRadii.button),
          side: border == null ? BorderSide.none : BorderSide(color: border!, width: 1.5),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(AppRadii.button),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.lg,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: foreground, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
