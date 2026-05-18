import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import 'login_screen.dart';

/// 403-style "you're in the wrong place" screen. Shown when the route guard
/// catches a Member/Leader at /cms or an Admin/Super-Admin at /m. The user
/// is signed in and valid — they just need to go to their portal.
class WrongPortalScreen extends StatelessWidget {
  const WrongPortalScreen({super.key, required this.expected});

  /// The audience this user belongs to. The screen offers a one-click jump
  /// to that portal.
  final PortalAudience expected;

  @override
  Widget build(BuildContext context) {
    final bool isAdminBound = expected == PortalAudience.webAdmin;
    return Scaffold(
      backgroundColor: AppColors.brandBrownDark,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(
                  Icons.lock_outline,
                  color: AppColors.goldOlive,
                  size: 56,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Wrong portal',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: AppColors.cream,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  isAdminBound
                      ? 'Your account is set up for the admin portal. The mobile app is for field officers only.'
                      : 'Your account is set up for the mobile app. The admin portal is for HQ staff only.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.cream.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBrown,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => context.go(expected.loginPath),
                  icon: const Icon(
                    Icons.arrow_forward,
                    color: AppColors.cream,
                  ),
                  label: Text(
                    isAdminBound
                        ? 'GO TO ADMIN PORTAL'
                        : 'GO TO MOBILE APP',
                    style: const TextStyle(
                      color: AppColors.cream,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Back to landing'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
